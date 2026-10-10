# Matrix chat (homeserver + LiveKit calls)

The chart can deploy the Matrix chat infrastructure: a Tuwunel homeserver and
a LiveKit media SFU for voice and video calls. Waldur's API issues the LiveKit
call tokens itself, and only to joined members of the room (see
[Calls](#calls)).

## Enabling

```yaml
matrixChat:
  enabled: true
  networkPolicy:
    enabled: true   # ships the livekit/homeserver NetworkPolicies; independent of the chart-wide networkPolicy.enabled
  homeserver:
    enabled: true
    serverName: matrix.example.org   # immutable; baked into every user/room ID
  livekit:
    enabled: true
    publicUrl: wss://matrix.example.org   # calls are offered only when this is set
    keys:
      apiKey: <key>
      apiSecret: <secret>
```

There is no registration token to invent, no LoadBalancer IP to copy back in
afterwards, and no Setup wizard to run — see
[Zero-touch setup](#zero-touch-setup) for what the chart does instead. The chart
also turns on the `project.show_matrix_chat` feature flag, without which Waldur
shows no chat drawer, project chat tab or Matrix admin page; set it in
`waldur.featureFlags` to override that.

`livekit.keys` (`apiKey` + `apiSecret`) supports `existingSecret` for external
secret managers, as does the generated token Secret
(`matrixChat.setup.existingSecret`).

## Zero-touch setup

The appservice `as_token` is a shared secret between two programs — Waldur and
the homeserver. Nobody expects Postgres to boot, generate its own password, and
show a wizard so you can paste it into Django's settings; the deployment picks
the password and hands the same value to both sides. `matrixChat.setup` (on by
default) treats the Matrix tokens the same way.

On install, a `pre-install`/`PreSync` Job mints an `as_token`, an `hs_token`, a
registration token and a bootstrap password into the `matrix-appservice-secret`
Secret. The homeserver mounts that Secret directly — which is also what stops it
starting before the Secret exists — and a second `post-install`/`PostSync` Job
writes the tokens into the backend's Constance settings with mastermind's
`waldur init_matrix_settings`. Neither Job ever prints token material; secrets are
logged only as `sha256:<first-12-hex>` fingerprints. The bootstrap password is
never written to Constance; only the registration step reads it.

**Upgrades never rotate the tokens.** The generating Job reads the existing
Secret and reuses it; it holds `get` and `create` on Secrets and deliberately not
`update` or `delete`, so it structurally cannot rotate a live token. A
registration carries exactly one `as_token`, so rotation is an unavoidable
cutover — if it happened behind your back the bot would silently start failing
with `M_UNKNOWN_TOKEN`. The Secret also survives `helm uninstall`, because Helm
never owned it: the Job creates it through the API rather than the chart
rendering it, and it carries no ArgoCD tracking label, so ArgoCD does not prune
it either. That matters, since losing these tokens while the homeserver's data
volume survives means losing the ability to talk to your own chat history.

**Why the Jobs use the Kubernetes API** rather than generating the tokens in a
template with `randAlphaNum` guarded by `lookup`: this chart ships
`applicationset.yaml`, so production runs on ArgoCD, where `lookup` returns empty
during server-side dry-run and diff rendering. ArgoCD would see a fresh random
token on every diff, report permanent drift, and rotate the token on an unrelated
sync. The Jobs run at sync time against a real API server instead, with a Role
scoped to one namespace.

That Role names what it touches wherever the verb allows: `get` on the setup
Secret and `create` on Secrets (a create cannot be limited by name), and only
the generating Job uses it. The wiring Job runs with no API token, and with
`existingSecret` the chart renders no Role at all. LiveKit's node-IP discovery runs under a ServiceAccount of its
own, `livekit-node-ip`, which can read the `livekit-rtc` Service and nothing
else. Only the discovery initContainer gets its token, so the internet-facing
media server holds none.

To manage the tokens yourself (Vault, Sealed Secrets, External Secrets
Operator), point `matrixChat.setup.existingSecret.name` at a Secret with
`as_token`, `hs_token` and `registration_token` keys — nothing is then
generated. Also include `bootstrap_password`: the registration step creates the
bootstrap admin with it on a new homeserver and signs in with it later. Without
it the first registration fails unless the Secret has an `admin_token`: the
command creates no bootstrap admin that nobody could sign in as. Each key name
is configurable under `existingSecret`.

The registration step needs admin rights to register or replace the
registration: on a new homeserver, after a rotation, and whenever the
homeserver's copy differs from Waldur's. It uses an optional `admin_token` key
(`existingSecret.adminTokenKey`) when the Secret has one: a homeserver admin's
access token, handed to the Job as `MATRIX_ADMIN_TOKEN`. Otherwise it signs in
as the bootstrap admin. The chart never generates `admin_token`. Add it for the
sync that needs it and remove it afterwards: the Job uses it ahead of the
bootstrap password, so a revoked token left there makes the next change fail.

**Older mastermind images.** The setup Jobs and LiveKit's node-IP discovery run
`matrix-init`, a script in the mastermind image, together with the
`init_matrix_settings` command it calls. An image without them cannot run the
setup: the secrets Job fails with `executable file not found`, and so does the
upgrade. Point `waldur.imageTag` at an image that has `matrix-init`, or turn
`setup.enabled` off. With `registerAppservice` on, the wiring Job also needs
`waldur register_matrix_appservice`. On an image without it, the Job logs a
warning, seeds Constance, skips the registration and exits 0, and chat stays
down until the appservice is registered.

While the chart seeds the tokens, the Setup wizard in Waldur refuses to rotate
them (it answers `409`): the next sync would write the old ones back. It knows
from the `MATRIX_TOKENS_MANAGED_BY` setting, which the wiring Job sets to
`deployment` on every run. The other way round, `init_matrix_settings` refuses
appservice tokens in Constance that the deployment did not seed, for example
from an earlier run of the Setup wizard: the wiring Job then fails and writes
nothing. A deployment that ran Matrix chat before `setup` existed hands its
tokens over as [Migrating an existing deployment](#migrating-an-existing-deployment)
describes.

### Migrating an existing deployment

Charts before `matrixChat.setup` took the registration token from
`homeserver.registrationToken` and left the appservice tokens to the Setup
wizard. `setup.enabled` is on by default now, so upgrading such a release
without preparation would have the setup Job mint new tokens: the homeserver
would restart with a registration token Waldur does not have, and the wiring
Job would refuse the appservice tokens the wizard configured. Hand the current
tokens to the setup Secret before upgrading instead.

1. Create `matrix-appservice-secret` from Waldur's current settings, with a new
   bootstrap password. The values go from the API pod straight into the Secret,
   never through a command line or a file:

   ```bash
   kubectl -n <namespace> exec deploy/waldur-mastermind-api -- waldur shell -c '
   import json, secrets
   from constance import config
   print("SECRET " + json.dumps({
       "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
       "metadata": {"name": "matrix-appservice-secret"},
       "stringData": {
           "as_token": config.MATRIX_APPSERVICE_AS_TOKEN,
           "hs_token": config.MATRIX_APPSERVICE_HS_TOKEN,
           "registration_token": config.MATRIX_USER_REGISTRATION_SECRET,
           "bootstrap_password": secrets.token_hex(32),
       },
   }))
   ' | sed -n 's/^SECRET //p' | kubectl -n <namespace> create -f -
   ```

   The keys are the ones the setup Jobs use: `as_token`, `hs_token`,
   `registration_token` and `bootstrap_password`, plus an optional
   `admin_token`. `registration_token` has to be the homeserver's current
   registration token, the value of `homeserver.registrationToken`. Earlier
   charts required Waldur's `MATRIX_USER_REGISTRATION_SECRET` to equal it, which
   is why it is read from there; if yours differ, put the homeserver's value in
   instead. To keep the tokens in your own secret manager, store the same keys
   there and set `setup.existingSecret.name`.

2. Remove `homeserver.registrationToken` and
   `homeserver.registrationTokenExistingSecret` from your values. With setup on,
   either is a render error. If you pinned `livekit.rtc.nodeIp`, also set
   `livekit.rtc.autoDiscoverNodeIp: false`, which is on by default now, or
   remove `nodeIp` to have the address discovered.

3. Upgrade as usual, deleting the init-whitelabeling job first, and with
   `--wait`, so that the wiring Job runs after the homeserver has restarted
   with the new configuration:

   ```bash
   kubectl -n <namespace> delete job waldur-mastermind-init-whitelabeling-job --ignore-not-found
   helm upgrade waldur waldur/ -n <namespace> -f <your values> --wait --timeout 20m
   ```

   The secrets Job finds the Secret and reuses it. The wiring Job seeds the same
   tokens into Waldur, which it accepts because they match what Waldur holds,
   and marks them as the deployment's from then on. The registration on the
   homeserver keeps working, and the Job reports it as already registered.
   It also warns that it could not compare the registration, because no
   `@waldur-bootstrap` exists yet; see below.

**The bootstrap admin.** The homeserver already has its own admins: the first
account registered on it, which earlier charts made an admin. The wiring Job
does not use them. It creates `@waldur-bootstrap` through the shared-secret
API, which the chart now keys with the registration token, but only when it
has to change the registration: at the first token rotation, say. While the
registration works it creates no account, and only warns that it could not
compare the registration. The shared-secret API works however many users and
admins the homeserver has, so `bootstrap_password` is all a later rotation
needs, provided no `@waldur-bootstrap` account exists from an earlier attempt.
If one does, put a homeserver admin's access token into the Secret under
`admin_token` for that sync and remove it afterwards. Review the existing
admins in `#admins:<serverName>`: the first account kept its admin rights, and
since this chart sets `grant_admin_to_first_user = false`, no account gains
them that way any more.

**If the upgrade ran without the Secret.** With plain Helm it cannot: an
upgrade that turns setup on while the `matrix-homeserver` StatefulSet runs and
the Secret is missing fails at render time and points here. ArgoCD renders
without access to the cluster, so the check cannot run there. The secrets Job
then mints new tokens and the wiring Job fails, with a pointer here, and
leaves Waldur's settings as they were, so the old tokens are still in Waldur.
To recover, delete the minted `matrix-appservice-secret`, create it as in step
1, sync again, and restart the homeserver, which read the minted registration
token at startup:
`kubectl -n <namespace> rollout restart statefulset/matrix-homeserver`.

### Opting out

To manage the tokens by hand again:

1. Set `matrixChat.setup.enabled: false` and supply the registration token
   again. Pointing `homeserver.registrationTokenExistingSecret` at
   `matrix-appservice-secret` (key `registration_token`) keeps the homeserver
   on the token it already has. LiveKit's node-IP discovery does not depend on
   setup and keeps working.
2. Under **Administration → Configuration → Matrix chat → Settings**, clear
   "Matrix Tokens Managed By" (`MATRIX_TOKENS_MANAGED_BY`). Nothing clears it
   for you: the chart stops running the wiring Job but leaves Constance as it
   is, and while the setting says `deployment` the Setup wizard keeps refusing
   to rotate the tokens.
3. Make sure the homeserver has an admin. Registering the appservice by hand,
   with `!admin appservices register` in `#admins:<serverName>`, needs one, and
   so does every token rotation. A homeserver that setup created already has
   `@waldur-bootstrap`, whose password stays in `matrix-appservice-secret`
   under `bootstrap_password`. A new homeserver with setup off has none:
   nothing creates the bootstrap admin, and the first account to register does
   not become an admin (`grant_admin_to_first_user = false`), because Waldur
   registers an account for whoever opens the chat first.

   Register an admin through the shared-secret API instead. The chart sets the
   homeserver's `registration_shared_secret` to the registration token with
   setup on or off, and no route reaches that API from outside the cluster.
   Run this in the API pod once the backend's `MATRIX_HOMESERVER_URL` and
   `MATRIX_USER_REGISTRATION_SECRET` are set (the latter to the registration
   token). It prints the account and its password, to sign in to a Matrix
   client with:

   ```bash
   kubectl -n <namespace> exec deploy/waldur-mastermind-api -- waldur shell -c '
   import hashlib, hmac, secrets, httpx
   from constance import config
   user, password = "homeserver-admin", secrets.token_hex(32)
   homeserver = httpx.Client(base_url=config.MATRIX_HOMESERVER_URL)
   nonce = homeserver.get("/_synapse/admin/v1/register").raise_for_status().json()["nonce"]
   mac = hmac.new(config.MATRIX_USER_REGISTRATION_SECRET.encode(),
                  "\0".join([nonce, user, password, "admin"]).encode(), hashlib.sha1)
   homeserver.post("/_synapse/admin/v1/register", json={
       "nonce": nonce, "username": user, "password": password, "admin": True,
       "mac": mac.hexdigest()}).raise_for_status()
   print(user, password)
   '
   ```

   With `homeserver.loginWithPassword: false` the account cannot sign in with
   that password: keep password login on until the appservice is registered.

The generated Secret stays where it is: Helm never owned it, so neither turning
setup off nor `helm uninstall` deletes it.

### Rotating the tokens

Rotation is a deployment operation:

1. Put new values for `as_token` and `hs_token` into the Secret, always both.
   Leave `registration_token` and `bootstrap_password` as they are:

   ```bash
   kubectl -n <namespace> patch secret matrix-appservice-secret --type merge -p \
     "{\"stringData\":{\"as_token\":\"$(openssl rand -hex 32)\",\"hs_token\":\"$(openssl rand -hex 32)\"}}"
   ```

2. Run `helm upgrade` (or sync in ArgoCD). The wiring Job seeds the new tokens
   into Constance, and with `registerAppservice` on (the default) it signs in
   with `admin_token` if the Secret has one, and as `@waldur-bootstrap`
   otherwise, unregisters the old registration and registers the new one.
   Tuwunel does not replace a registration that is registered again under the
   same id, which is why the old one is removed first. With it off, chat is
   down from this sync until you register the new tokens by hand.
3. The Job fails if the homeserver still rejects the new `as_token` afterwards.

Nothing reads the new values until step 2, so chat keeps working on the old
tokens until then; it is down only for the seconds between the Job seeding the
new tokens and replacing the registration. Events sent in those seconds, such as a
bot command, are not delivered to Waldur.

Step 1 changes both because either may have leaked. A new `hs_token` alone is
detected too: the Job compares the homeserver's copy of the registration with
Waldur's.

Do not delete the Secret to rotate:
the Job would also mint a new bootstrap password, which no longer matches the
bootstrap user on the homeserver, and the registration step would fail.

**The registration token** rotates separately, and needs a restart:

1. Put a new `registration_token` into the Secret.
2. Run `helm upgrade` (or sync). The wiring Job seeds it into the backend's
   `MATRIX_USER_REGISTRATION_SECRET`.
3. Restart the homeserver, which reads the token from the Secret, as its
   registration token and its `registration_shared_secret`, in environment
   variables at pod start. Nothing in the chart restarts it when the Secret
   changes: the Job generates the Secret, so the pod's checksum of the chart
   values cannot see it.

   ```bash
   kubectl -n <namespace> rollout restart statefulset/matrix-homeserver
   ```

Until step 3 the homeserver still holds the old token while Waldur offers the
new one, so run the two back to back. Existing users and rooms are not affected.

**With `setup.existingSecret`** the Secret belongs to your secret manager. Rotate
the values there and wait for it to sync the Secret. Then run `helm upgrade` (or
sync) as above, and restart the homeserver if the registration token changed.

#### Rotating with password login off

With `homeserver.loginWithPassword: false`, as with single sign-on, the
bootstrap admin cannot sign in. A sync with working tokens then cannot read the
homeserver's copy of the registration, so it only warns and changes nothing,
and step 2 of a rotation fails after seeding the new tokens, with "Password
login is disabled on the homeserver". For a rotation, or to apply a changed
registration, either set `loginWithPassword: true` for that sync and back to
`false` afterwards (the homeserver restarts on each change), or put an
`admin_token` into the Secret, along with the new tokens in step 1 of a
rotation, and remove it after the sync.

To get a token, register a temporary admin through the shared-secret API, as
[Token rotation](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#token-rotation)
in the setup guide describes. On helm, run it in the API pod, which reaches the
homeserver and holds the registration token in Constance, so the registration
token never passes through a command line. It prints the account and its
access token:

```bash
kubectl -n <namespace> exec deploy/waldur-mastermind-api -- waldur shell -c '
import hashlib, hmac, secrets, httpx
from constance import config
user, password = "rotation-" + secrets.token_hex(4), secrets.token_hex(32)
homeserver = httpx.Client(base_url=config.MATRIX_HOMESERVER_URL)
nonce = homeserver.get("/_synapse/admin/v1/register").raise_for_status().json()["nonce"]
mac = hmac.new(config.MATRIX_USER_REGISTRATION_SECRET.encode(),
               "\0".join([nonce, user, password, "admin"]).encode(), hashlib.sha1)
print(user, homeserver.post("/_synapse/admin/v1/register", json={
    "nonce": nonce, "username": user, "password": password, "admin": True,
    "mac": mac.hexdigest()}).raise_for_status().json()["access_token"])
'
```

After the sync, have the temporary admin deactivate itself in the admin room,
with the deactivate step under the same
[Token rotation](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#token-rotation)
section, run with `HOMESERVER=https://<serverName>` and `TOKEN=<token>`. It uses
only the public client API. That also signs it out, and nobody can sign in to
the account again, not even through single sign-on. The step exits non-zero if
the temporary admin is still active; then deactivate it from `#admins` by hand.

Calls need encrypted transports. With `livekit.publicUrl` set, the chart
refuses to render unless `publicUrl` is a `wss://` URL and `apiScheme` is
`https`: clients send their Matrix OpenID token to Waldur's call token API and
their LiveKit token on the signalling websocket, and both are bearer
credentials. On a local or kind cluster without TLS, set
`matrixChat.livekit.allowInsecureTransport: true` to allow `ws://` and `http`.

## Image pinning

Images are pinned to specific versions by default — never `latest`:

- **homeserver** — `ghcr.io/matrix-construct/tuwunel`, pinned to the single
  supported version (see below). Set `homeserver.imageDigest` to pin immutably by
  digest.
- **livekit** — `livekit/livekit-server`, pinned by tag; `livekit.imageDigest`
  available. Pulled from `livekit.imageRegistry` (`docker.io` by default) — its
  own key, **not** `global.imageRegistry`, so pointing `global` at a private
  mirror doesn't rewrite LiveKit to a registry that has no such image. Override
  `livekit.imageRegistry` if you mirror it.

## Supported homeserver version

Waldur bundles the homeserver, so its version is ours to support, not yours to
choose. **One version is supported at a time**, the same across both packaging
paths:

| Path | Value |
| --- | --- |
| Helm | `matrixChat.homeserver.imageTag` |
| Docker Compose | `WALDUR_TUWUNEL_IMAGE_TAG` |

Both are `v1.9.3`. Do not set a version we do not ship, and do not let the two
diverge.

### Upgrading

Tuwunel migrates its embedded database in place on the first boot of a new
version, before it opens its port. From 1.9.1 a long migration logs its phase and
progress every fifteen seconds; earlier versions log nothing while it runs. Every
minor release so far has done this, so read the
[upstream release notes](https://github.com/matrix-construct/tuwunel/releases)
before moving in either direction.

1. Scale the homeserver StatefulSet to zero and snapshot the PVC.
2. Bump `imageTag` and run `helm upgrade --timeout 20m`, longer than
   `matrixChat.setup.homeserverWaitTimeout` plus a margin. With the default
   five minutes, a long migration marks the release failed while the wiring Job
   is still waiting. Do not add `--atomic`, and do not `helm rollback` a failed
   release: both point the tag back at the older Tuwunel, the downgrade warned
   about below. ArgoCD has no such limit.
3. Let the first boot finish. A pod that is slow to become ready is migrating,
   not hung. The chart's `startupProbe` keeps liveness off for up to six hours
   so Kubernetes does not kill it mid-migration, which corrupts the database.
   The wiring Job waits `matrixChat.setup.homeserverWaitTimeout` (15 minutes by
   default) for the homeserver before registering the appservice, then fails;
   Constance is seeded by then, and the next sync retries the registration.
4. Check `/_matrix/client/versions`, then `/api/admin/matrix/diagnostics/` on
   the Waldur side.

**Downgrades are the dangerous direction.** An older Tuwunel starts cleanly on
a migrated database and then silently serves stale data from the old stores. A
successful downgrade boot means nothing. Roll back by restoring the snapshot,
never by re-pointing the tag at an older image.

From 1.9.2, rooms are created as room version 12 by default. Existing rooms keep
their version. In a version 12 room the creator, the Waldur bot, has the highest
power level by definition and can never be listed in the room's power levels.

`serverName` is immutable: it is baked into every user and room ID. From 1.9.0
the homeserver stamps it into the database and refuses to boot under another
name:

```text
Critical error starting server: Database belongs to old.example; configured server name is new.example. Cannot reuse.
```

Restore the original `serverName`; do not wipe the PVC, which is the chat
corpus.

### CVE response

Tuwunel publishes advisories on its
[GitHub repository](https://github.com/matrix-construct/tuwunel/security/advisories).
Both the client-server and federation surfaces are exposed through the Matrix
ingress.

- Fix in a patch release of the supported minor: bump both packaging paths and
  ship a chart patch release.
- Fix needs a minor or major jump: follow the upgrade procedure above, verify
  on a restored snapshot first, bump both paths together.
- No fixed release yet: `matrixChat.enabled=false` removes the homeserver and
  its ingress; the PVC and its history are kept. Waldur keeps offering chat
  until you also switch `MATRIX_ENABLED` off under **Administration →
  Configuration → Matrix chat → Settings** and hide it with
  `waldur.featureFlags: {"project.show_matrix_chat": false}`.

## Token lifetimes

Waldur's chat drawer signs in with a refresh token, so its access tokens
expire and are renewed in the background:

| Tuwunel key | Helm value | Default |
| --- | --- | --- |
| `access_token_ttl` | `homeserver.accessTokenTtl` | `300` (5 min) |
| `refresh_token_ttl` | `homeserver.refreshTokenTtl` | `86400` (24 h) |

Docker Compose sets the same values in `config/matrix/tuwunel.toml.template`.

The refresh lifetime is an idle timeout: each refresh moves the deadline
forward, so a drawer in use never expires, and a page left silent for a day
(e.g. on a suspended laptop) starts a new session through Waldur. `0` means the
refresh token never expires; the access token lifetime must be positive, as
Tuwunel reads `0` as "expire immediately". When a user starts a session, Waldur
also signs out that user's chat devices idle for more than 24 hours, so a
longer refresh lifetime, or `0`, only keeps the devices of users who start no
other session.

Clients that sign in without a refresh token, such as Element with a password,
get non-expiring tokens and are unaffected.

Tuwunel reads its configuration only at startup, so restart it after changing
either value: `kubectl rollout restart statefulset/matrix-homeserver`.

## Password mode for Matrix clients

With `MATRIX_EXTERNAL_LOGIN_METHOD` set to `password`, users generate a Matrix
password in Waldur and sign in to Element with it. It is meant for testing and
sites without an identity provider; production uses single sign-on. Set the
method under **Administration → Configuration → Matrix chat → Settings**, or
with `waldur.settingsOverrides: {MATRIX_EXTERNAL_LOGIN_METHOD: password}`, and
keep `homeserver.loginWithPassword: true`.

Waldur sets the passwords through the homeserver's admin API, so the bot has to
be a homeserver admin; see
[Making the bot a homeserver admin](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#making-the-bot-a-homeserver-admin)
for what that costs. On helm, sign in to a Matrix client such as Element, with
the homeserver `https://<serverName>`, as `@waldur-bootstrap:<serverName>` with
the bootstrap password:

```bash
kubectl -n <namespace> get secret matrix-appservice-secret \
  -o jsonpath='{.data.bootstrap_password}' | base64 -d
```

In the `#admins:<serverName>` room, send
`!admin users make-user-admin @<setup.botLocalpart>:<serverName>`, then sign
out.

## Runtime steps, and what now handles them

Four steps used to be manual, and all four failed silently when skipped. With
`setup.enabled` the chart handles all four.

1. **Backend token match** — handled. Both sides are given the same generated
   value; there is no `homeserver.registrationToken` to keep in sync any more,
   and setting one while `setup.enabled` is true is a render error rather than a
   value that is quietly ignored.
2. **Appservice registration** — handled by
   `matrixChat.setup.registerAppservice` (default on). Tuwunel registers
   appservices at runtime via the `!admin appservices register` admin-room
   command rather than from config, so the wiring Job drives that command
   through the mastermind image's `register_matrix_appservice`, as a bootstrap
   admin it creates itself.

   On a new homeserver the command creates `@waldur-bootstrap` through the
   shared-secret registration API, with admin rights and `bootstrap_password`
   as its password. The chart sets the homeserver's
   `registration_shared_secret` to the registration token, and the API answers
   only inside the cluster: the chart routes no `/_synapse` path. That first
   run uses the token the registration returns, so it works with password
   login off. Later runs sign in as `@waldur-bootstrap` with that password, and
   every run signs the bootstrap session out when it is done. No account becomes an admin by being
   the first one (`grant_admin_to_first_user = false`), so the users Waldur
   registers stay ordinary users. `forbidden_usernames` does not block the
   shared-secret API, so single sign-on can be on from the first install.

   Leaving it on across upgrades is safe. Every sync signs in, compares the
   homeserver's registration with Waldur's and replaces it when the URL, a
   token or a namespace differs, losing a few seconds of events; otherwise it
   changes nothing. Without admin access it leaves a working registration
   alone with a warning, and fails only when Waldur turns the homeserver's ping
   away.
   [Registering on Tuwunel from the command line](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#registering-on-tuwunel-from-the-command-line)
   has the details.

   With `registerAppservice: false` nothing registers the appservice: chat
   stays down until you register it by hand, and every token rotation needs the
   same again, since the homeserver keeps the old registration. Run the command
   in the API pod, handing it the bootstrap password on standard input so that
   it stays out of the command line:

   ```bash
   kubectl -n <namespace> get secret matrix-appservice-secret \
     -o jsonpath='{.data.bootstrap_password}' | base64 -d |
     kubectl -n <namespace> exec -i deploy/waldur-mastermind-api -- sh -c \
       'read -r MATRIX_BOOTSTRAP_PASSWORD; export MATRIX_BOOTSTRAP_PASSWORD;
        exec waldur register_matrix_appservice --url http://waldur-mastermind-api.<namespace>.svc'
   ```

   To use a homeserver admin's access token instead, pipe that in and read it
   into `MATRIX_ADMIN_TOKEN`. To paste the registration into the admin room
   yourself, `waldur generate_appservice_registration --url
   http://waldur-mastermind-api.<namespace>.svc` in the API pod prints it.
3. **LoadBalancer IP** — handled by `livekit.rtc.autoDiscoverNodeIp` (default
   on). An initContainer reads the `livekit-rtc` Service's assigned external
   address at pod start and writes it into LiveKit's config as `node_ip`.
   Because it runs on every pod start rather than once at install, a LoadBalancer
   that is reprovisioned with a different address self-heals on restart. Setting
   `rtc.nodeIp` as well is a render error — pin it *or* discover it, not both.

   The initContainer waits up to five minutes for the address, logging every
   30 seconds, then exits non-zero; the pod sits in `Init:Error` /
   `Init:CrashLoopBackOff` and the kubelet keeps retrying. There is no fallback
   to LiveKit's own STUN discovery, which picks the wrong address behind a
   cluster LoadBalancer: LiveKit would boot fine and every call would connect
   with no media. A LoadBalancer that reports a hostname instead of an IP (AWS
   ELB/NLB) is resolved to an address once per pod start, IPv4 first; restart
   the pod if that address changes.
4. **Homeserver URL** — handled. The wiring Job seeds `MATRIX_HOMESERVER_URL`
   with the homeserver's in-cluster Service
   (`http://matrix-homeserver.<namespace>.svc:<clientPort>`), where Waldur
   calls it for chat and to verify call tokens, and
   `MATRIX_HOMESERVER_PUBLIC_URL` with `https://<serverName>`. Calls therefore
   do not depend on pods reaching the ingress's public address.

## The Matrix bot

`matrixChat.bot` deploys mastermind's `matrix_bot` command, Waldur's member of
every Waldur room. It runs on a Matrix device of its own and holds that
device's keys, so it is the only process that can post into an encrypted room
or read the commands sent to it there. While it runs, every message Waldur
sends as the bot (role, order and staff notices, command replies) goes through
it. Without it, Waldur posts directly, which works only in rooms that are not
encrypted.

- **Exactly one replica.** The bot holds a lease in Waldur's database, and a
  second one refuses to start while the first holds it, so the Deployment uses
  the `Recreate` strategy: the old pod releases the lease before the new one
  starts.
- **No volume.** Its keys live in Waldur's database, in a `matrix_bot`
  schema, pickled under a key stored encrypted with `FIELD_ENCRYPTION_KEY`.
  Database backups carry them, and losing that key makes the store unreadable:
  the bot then refuses to start rather than reset its identity.
- It needs the appservice registered (step 2 of
  [Runtime steps](#runtime-steps-and-what-now-handles-them)) and reaches the homeserver
  at `MATRIX_HOMESERVER_URL`, like the API.
- **Restoring a database elsewhere** (a staging copy of production, say) copies
  the bot's identity with it. Disable `matrixChat.bot` there, or drop the copy's
  `matrix_bot` schema and `matrix_chat_matrixbotidentity` rows, before the bot
  starts: otherwise a second bot runs as the same device, can read the
  original's rooms, and corrupts both bots' sessions.

## Calls

Matrix clients find calls in the homeserver's `.well-known/matrix/client`. With
`livekit.publicUrl` set, the chart advertises one RTC focus there
(`org.matrix.msc4143.rtc_foci`):

```json
{"type": "livekit", "livekit_service_url": "https://<apiHostname>/api/matrix/livekit"}
```

Element (Web, Desktop and mobile, through Element Call) and Waldur's chat
drawer both read it and ask Waldur's API for a LiveKit token:
`POST /api/matrix/livekit/get_token`, or the legacy `/api/matrix/livekit/sfu/get`
that Element Call falls back to. Waldur verifies the caller's Matrix OpenID
token with the homeserver, checks that the caller is joined to the room now and
that the device is theirs, and answers with the LiveKit URL and a token for
that room only. Anyone else gets `403`.

The chart wires what this needs:

- **Settings.** The chart seeds `MATRIX_LIVEKIT_PUBLIC_URL`
  (`livekit.publicUrl`), `MATRIX_LIVEKIT_URL` (the bundled LiveKit's in-cluster
  Service, or an external LiveKit's public URL as `https://`), and
  `MATRIX_LIVEKIT_KEY` / `MATRIX_LIVEKIT_SECRET` from the LiveKit Secret. With
  `setup.enabled` (the default) the wiring Job seeds them with the other Matrix
  settings, through `init_matrix_settings`, which fails the Job on a value it
  rejects; with setup off the init-whitelabeling job does. They are overwritten
  on every `helm upgrade`, like the other seeded settings; a
  `waldur.settingsOverrides` entry for either URL takes precedence, and one for
  the key or the secret is a render error while setup is on. The
  bundled LiveKit's room API (`/twirp`) is not routed through the ingress, so
  keep `MATRIX_LIVEKIT_URL` on the in-cluster Service; only the signalling
  websocket (`/rtc`) is public. With
  `waldur.initdbEnabled: false` nothing is seeded: set them under
  Administration -> Settings instead.
- **Cross-origin access.** Element calls the API from another origin. Waldur
  answers these two paths with `Access-Control-Allow-Origin: *` and no
  credentials. ingress-nginx's `enable-cors` on the API ingress would replace
  that with the caller's origin plus credentials, so on nginx the chart routes
  `/api/matrix/livekit` through a separate `api-matrix-livekit-ingress` without
  it. Traefik's API middleware already answers with `*`.
- **Homeserver access.** Waldur checks OpenID tokens at
  `/_matrix/federation/v1/openid/userinfo` on `MATRIX_HOMESERVER_URL`, the
  in-cluster client port. Tuwunel serves that endpoint with federation off too,
  so calls do not depend on `homeserver.allowFederation`, public DNS or
  hairpin routing to `serverName`.

A call that shows **Could not connect to the call.** usually fails at the
token request; check it in the browser's network tab. `403` means Waldur
refused the caller (not joined to the room, or an unknown device). `503` means
Waldur could not reach the homeserver or LiveKit, or the LiveKit settings above
are missing.

### Upgrading from lk-jwt-service

Earlier charts deployed `lk-jwt-service` to issue call tokens. Waldur issues
them now, and the service is removed:

1. Delete `matrixChat.lkJwt` and `matrixChat.homeserver.livekitServiceUrl` from
   your values. The chart ignores both; the RTC focus now always points at
   Waldur's API.
2. Upgrade the chart together with a Waldur image that serves
   `/api/matrix/livekit` (delete the init-whitelabeling job first, as usual).
   `helm upgrade` removes the lk-jwt-service Deployment, Service,
   NetworkPolicy and its `/get_token` and `/sfu` routes.
3. Restart the homeserver so it reads the new `.well-known`:
   `kubectl rollout restart statefulset/matrix-homeserver`.
4. Calls already running keep their LiveKit connection. Clients pick up the new
   focus the next time they read `.well-known`; reloading Element or the
   Waldur page is enough.

## Open-registration guard

With `setup.enabled` (the default) the registration token is always generated, so
this guard cannot trip. With `setup.enabled: false`, if
`homeserver.allowRegistration` is `true` but no `registrationToken` (or
`registrationTokenExistingSecret`) is set, the chart **refuses to render** — this
prevents shipping an open, abusable homeserver. Provide a token, or set
`allowRegistration: false`.

The chart fails the render in these further cases, to turn silent runtime
breakage into an obvious config error:

- `matrixChat.enabled` with **`homeserver.enabled: false`** — the homeserver is a
  bundled component, and the appservice is deliberately a root account over the
  whole `@.*:<domain>` namespace, so pointing Waldur at someone else's homeserver
  is unsafe by design and unsupported. This used to render cleanly and produce a
  deployment with no homeserver, no matrix ingress, and no chat host in the
  homeport CSP.
- `setup.enabled` with **`homeserver.registrationToken`** or
  **`homeserver.registrationTokenExistingSecret`** also set (the token comes
  from the setup Secret, so a second value would drift), or with
  `waldur.initdbEnabled: false` (Constance seeding needs a migrated database).
- `livekit.rtc.autoDiscoverNodeIp` together with an explicit **`rtc.nodeIp`**, or
  with **neither** of the two.

- `livekit.enabled` with **no credentials** (neither `livekit.keys.apiKey` +
  `apiSecret` nor `livekit.keys.existingSecret.name`) — otherwise livekit-server
  starts with no signing key and Waldur cannot sign call tokens.
- `livekit.keys.apiSecret` shorter than **32 characters** — livekit-server only
  warns and starts anyway, shipping a weak signing key.
- `livekit.turn.enabled` with **no `turn.domain`** or **no `turn.tls.existingSecret`**
  — a TURN relay with no reachable hostname or no cert boots but never accepts a
  connection, so the clients that need it (symmetric NAT) fail silently.

## Why the RTC LoadBalancer

WebRTC media is UDP/TCP and cannot traverse an L7 ingress, so `livekit-rtc` is a
LoadBalancer — the only one in the chart. Signaling (wss) and everything else
ride the shared matrix ingress on `serverName`.

## TURN relay (clients behind symmetric NAT)

By default LiveKit only offers **direct host candidates** (`rtc.udpPort` /
`rtc.tcpPort` on `rtc.nodeIp`). A client on a cone NAT connects fine, but a client
behind a **symmetric NAT** — corporate CGNAT, or **iCloud Private Relay** — reaches
signaling and then has every ICE pair fail: the call joins but carries no media.
The only fix is a TURN relay both peers connect *out* to.

Enable LiveKit's built-in **TURNS** (TURN over TLS) — no separate coturn pod:

```yaml
matrixChat:
  livekit:
    turn:
      enabled: true
      domain: turn.matrix.example.org   # must resolve to the livekit-rtc LB IP
      tlsPort: 5349
      tls:
        existingSecret: livekit-turn-tls  # cert/key for `domain`
```

Two things the operator must wire (the chart can't):

1. **DNS.** `turn.domain` must resolve to the **`livekit-rtc` LoadBalancer IP**
   (the same target as `rtc.nodeIp`) — *not* `serverName`, which points at the
   matrix ingress where nothing listens on `tlsPort`. Use a dedicated name, e.g.
   `turn.<serverName>`. TURNS rides the rtc LoadBalancer because TURN is its own
   protocol and can't go through the L7 ingress.
2. **Cert.** LiveKit terminates the TURNS TLS itself, so it needs a cert + key for
   `turn.domain` in `turn.tls.existingSecret` (e.g. a cert-manager `Certificate`).

TURNS on `tlsPort` also tunnels through TLS-only firewalls, so it covers both
symmetric NAT and restrictive networks. Plain TURN/UDP is intentionally not
exposed — relayed media always rides TLS.

## What the chart wires automatically

- **Homeport CSP.** Enabling matrix injects the homeserver host into the homeport
  Content-Security-Policy: `connect-src` gets `https://<serverName>` (chat sync)
  and `wss://<serverName>` (call signaling); `media-src`/`img-src` get
  `https://<serverName>` (chat media/images). Without this the browser would block
  the chat client and calls. No action needed — it follows `homeserver.serverName`
  and is a no-op when matrix is disabled.
- **WebAssembly in the homeport CSP.** `script-src` always includes
  `'wasm-unsafe-eval'`. Chat is end-to-end encrypted, and the browser runs the
  encryption as WebAssembly, which it refuses to compile without this source. It
  allows compiling WebAssembly only, not `eval()` of JavaScript. Without it the
  chat drawer reports that encryption is unavailable in this browser.
- **NetworkPolicies.** When `matrixChat.networkPolicy.enabled` is `true`, the chart
  adds a policy per pod. This gate is independent of the chart-wide
  `networkPolicy.enabled` (which only covers the homeport/mastermind-api
  policies) — set it to ship the matrix/livekit policies without opting the
  rest of the stack into NetworkPolicy. The livekit policy accepts media from
  **anywhere** (external WebRTC). The homeserver policy accepts HTTP from
  **anywhere** on its service port too, because browser requests reach it
  through the ingress controller, which runs in its own namespace. Egress is
  left open on both, for federation.

## Using an external LiveKit

You can run the Matrix calling stack against an **operator-managed LiveKit SFU**
instead of the bundled `livekit-server` — the same bring-your-own-backend pattern
the chart offers for PostgreSQL. Tuwunel stays bundled; only the SFU is external.

Why it works: the browser reaches LiveKit client-side via the URL Waldur returns
with each call token (`livekit.publicUrl`), and Waldur signs those tokens with an
API key/secret it shares with the LiveKit server. Waldur also calls the external
LiveKit's room API at the same address over `https://`. Point both at your
external instance and the bundled SFU is never needed.

Configuration:

```yaml
matrixChat:
  enabled: true
  livekit:
    enabled: false                              # don't deploy the bundled SFU
    publicUrl: "wss://livekit.operator.example" # your external LiveKit's wss endpoint
    keys:
      existingSecret:
        name: operator-livekit-creds            # REQUIRED for external LiveKit
        apiKeyKey: LIVEKIT_API_KEY
        apiSecretKey: LIVEKIT_API_SECRET
  homeserver:
    enabled: true                               # Tuwunel stays bundled
    serverName: matrix.example.org
```

The `existingSecret` must hold the **same** API key and secret configured on your
external LiveKit, under the keys named above. If you omit `existingSecret.name`
while `livekit.enabled=false`, the chart refuses to render — the bundled
`livekit-secret` only exists when the bundled server is deployed, so Waldur
would have no key to sign call tokens with.

With `livekit.enabled=false` the chart drops the in-cluster LiveKit Service, its
`config.yaml`, network policy, RTC LoadBalancer, and the `/rtc` ingress
route. The browser connects straight to `publicUrl`, so reachability, TLS, and the
media plane are the external operator's responsibility.
