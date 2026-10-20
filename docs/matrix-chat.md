# Matrix chat with Helm

The chart can deploy the Matrix chat infrastructure: a Tuwunel homeserver and
a LiveKit media SFU for voice and video calls. Waldur's API issues the LiveKit
call tokens itself, and only to joined members of the room (see
[Calls](#calls)).

## Enabling

```yaml
apiScheme: https   # the chart refuses calls over http; see below
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

While the chart seeds the tokens, the Setup wizard in Waldur refuses to rotate
them (it answers `409`): the next sync would write the old ones back. It knows
from the `MATRIX_TOKENS_MANAGED_BY` setting, which the wiring Job sets to
`deployment` on every run. The other way round, `init_matrix_settings` refuses
appservice tokens in Constance that the deployment did not seed, for example
from a run of the Setup wizard while setup was off: the wiring Job then fails
and writes nothing. To hand the tokens to the deployment, clear
`MATRIX_APPSERVICE_AS_TOKEN` and `MATRIX_APPSERVICE_HS_TOKEN` under
**Administration → Configuration → Matrix chat → Settings** and sync again,
which registers the appservice with the Secret's tokens.

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

   Register a temporary admin through the shared-secret API instead, as
   [Rotating with password login off](#rotating-with-password-login-off)
   describes. The snippets read the secret from Waldur's
   `MATRIX_USER_REGISTRATION_SECRET`, which has to be the registration token
   that step 1 gives the homeserver: the chart sets the homeserver's
   `registration_shared_secret` to that token with setup on or off. The
   registration answers with the admin's access token, which works with
   password login off too. Hand it to `register_matrix_appservice` as
   `MATRIX_ADMIN_TOKEN`, as under
   [Runtime steps](#runtime-steps-and-what-now-handles-them), then have the
   admin deactivate itself.

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

Treat the `as_token` as a homeserver admin credential. Waldur's registration
claims every local user ID, so from the moment the appservice is registered the
token can act as any account on the homeserver, `@waldur-bootstrap` and the
other admins included. The registration step also makes the bot a homeserver
admin, so the token can call the admin API as the bot too, for example to set
any account's password. Waldur staff can read it in clear through the settings
API. See
[Making the bot a homeserver admin](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#making-the-bot-a-homeserver-admin).

The tokens also end up outside the Secret. Each registration is posted to
`#admins:<serverName>` as a plain message, both tokens included, and stays in
that room's history on the homeserver's PVC; a rotation makes the old ones
useless. Tuwunel 1.9.3 sends the `hs_token` in the URL of every call to Waldur,
and when a call cannot reach Waldur's API its warning quotes that URL, so the
token lands in the homeserver's log. Treat those logs as secret, and rotate both
tokens if they were shipped anywhere less trusted than the cluster.

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

To get a token, register a temporary admin with the two snippets under
[Token rotation](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#token-rotation)
in the setup guide, and after the sync have it deactivate itself. They read the
homeserver URL and the registration secret from Waldur's settings, so run them
in the API pod, which reaches the homeserver's admin API inside the cluster;
nothing outside does. The token goes into the Secret through standard input,
never on a command line:

```bash
TOKEN=$(kubectl -n <namespace> exec deploy/waldur-mastermind-api -- \
  waldur shell -c '<first snippet from the guide>' | sed -n 's/^TOKEN //p')
printf '{"stringData":{"admin_token":"%s"}}' "$TOKEN" |
  kubectl -n <namespace> patch secret matrix-appservice-secret --type merge --patch-file /dev/stdin
```

After the sync, remove `admin_token` from the Secret and have the admin
deactivate itself:

```bash
kubectl -n <namespace> patch secret matrix-appservice-secret --type json \
  -p '[{"op": "remove", "path": "/data/admin_token"}]'
printf '%s\n' "$TOKEN" | kubectl -n <namespace> exec -i deploy/waldur-mastermind-api -- \
  waldur shell -c '<second snippet from the guide>'
unset TOKEN
```

Calls need encrypted transports. With `livekit.publicUrl` set, the chart
refuses to render unless `publicUrl` is a `wss://` URL and `apiScheme` is
`https`: clients send their Matrix OpenID token to Waldur's call token API and
their LiveKit token on the signalling websocket, and both are bearer
credentials. On a local or kind cluster without TLS, set
`matrixChat.livekit.allowInsecureTransport: true` to allow `ws://` and `http`.

Chat has no such check, but needs HTTPS just as much: Waldur's session
response carries the user's Matrix tokens and recovery key. With the defaults,
`apiScheme: "http"` and `ingress.tls.enabled: false`, the chart's ingresses
serve it over plain HTTP. Set `apiScheme: "https"`, and terminate TLS at the
ingresses or in front of them. TLS alone is not enough: homeport's API URL,
the homeserver's well-known client URL and `MATRIX_HOMESERVER_PUBLIC_URL` are
all built from `apiScheme`, so with `http` clients are still sent to `http://`
URLs.

## Image pinning

The homeserver and LiveKit images are pinned to specific versions by default,
by tag — never `latest`:

- **homeserver** — `ghcr.io/matrix-construct/tuwunel`, pinned to the single
  supported version (see below). Set `homeserver.imageDigest` to pin immutably by
  digest.
- **livekit** — `livekit/livekit-server`, pinned by tag; `livekit.imageDigest`
  available. Pulled from `livekit.imageRegistry` (`docker.io` by default) — its
  own key, **not** `global.imageRegistry`, so pointing `global` at a private
  mirror doesn't rewrite LiveKit to a registry that has no such image. Override
  `livekit.imageRegistry` if you mirror it.

A tag can be moved to another image; only a digest cannot. The homeserver pod's
`render-config` init container and the bot's `check-db-ready` run
`postgres:17` (`waldur.initdbImageName`), a tag that follows every 17.x
release; mirror it if every image must stay fixed. The bot itself runs Waldur's
image, at `waldur.imageDigest` when that is set, else at `waldur.imageTag`.

## Supported homeserver version

Waldur bundles the homeserver, so its version is ours to support, not yours to
choose. **One version is supported at a time**, the same across both packaging
paths:

| Path | Value |
| --- | --- |
| Helm | `matrixChat.homeserver.imageTag` |
| Docker Compose | `WALDUR_TUWUNEL_IMAGE_TAG` |

Both are `v1.9.3`. Do not set a version we do not ship, and do not let the two
diverge. Waldur's chat drawer is built around details of this version: for
example, it fetches the dehydrated device's queued events with the `POST`
Tuwunel serves, not the `GET` matrix-js-sdk sends.

### Upgrading

Tuwunel migrates its embedded database in place on the first boot of a new
version, before it opens its port. From 1.9.1 a long migration logs its phase and
progress every fifteen seconds; earlier versions log nothing while it runs. Every
minor release so far has done this, so read the
[upstream release notes](https://github.com/matrix-construct/tuwunel/releases)
before moving in either direction.

1. Scale the homeserver StatefulSet to zero and back the PVC up (see
   [Backup and restore](#backup-and-restore)).
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

`serverName` is immutable: it is baked into every user and room ID. The
homeserver stamps it into the database and refuses to boot under another
name:

```text
Critical error starting server: Database belongs to old.example; configured server name is new.example. Cannot reuse.
```

Restore the original `serverName`; do not wipe the PVC, which is the chat
corpus.

### CVE response

Tuwunel fixes security issues in its next release and does not backport them.
Its security policy promises a
[GitHub security advisory](https://github.com/matrix-construct/tuwunel/security/advisories)
with each fixing release, but it has published none so far, not even for the
federation disclosure fixed in 1.9.0: the fixes are described only in the
[release notes](https://github.com/matrix-construct/tuwunel/releases). Watch
the releases and read each one's notes for security fixes. Both the
client-server and federation surfaces are exposed through the Matrix ingress.

- Fix in a patch release of the supported minor: bump both packaging paths and
  ship a chart patch release.
- Fix needs a minor or major jump: follow the upgrade procedure above, verify
  on a restored snapshot first, bump both paths together.
- No fixed release yet: `matrixChat.enabled=false` removes the homeserver and
  its ingress; the PVC and its history are kept. Waldur keeps offering chat
  until you also switch `MATRIX_ENABLED` off under **Administration →
  Configuration → Matrix chat → Settings** and hide it with
  `waldur.featureFlags: {"project.show_matrix_chat": false}`. To turn chat
  back on, set `matrixChat.enabled=true`, remove that `featureFlags` entry and
  switch `MATRIX_ENABLED` on again: the wiring Job switches it on only at the
  first seeding. To keep the switch in your values instead, set
  `waldur.settingsOverrides.MATRIX_ENABLED`, which the chart applies on every
  sync.

## Backup and restore

Back up these four together, with the bot and the homeserver stopped.
[Backup and restore](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#backup-and-restore)
in Waldur's admin guide says what each holds, why they must come from the same
moment, and why a history export is not a backup.

| What | Holds |
|---|---|
| PVC `data-matrix-homeserver-0`, or `homeserver.persistence.existingClaim` | The homeserver's database, media included |
| Secret `matrix-appservice-secret`, or `setup.existingSecret` | The appservice and registration tokens, and the bootstrap password registration signs in with. It survives `helm uninstall`, but not the namespace |
| Waldur's database | Rooms and Matrix profiles, the tokens in Constance, users' escrowed recovery keys, the bot's keys (schema `matrix_bot`), and the history exports, files included: Waldur's default `DatabaseStorage` keeps them in the database, encrypted, each export's key in its row. See [PostgreSQL backup configuration](postgres-backup-management.md) |
| `waldur.secretKey` and `waldur.fieldEncryptionKey`, or their Secrets | `FIELD_ENCRYPTION_KEY`, or a key derived from `SECRET_KEY` while it is unset (the chart's default), unlocks the recovery keys, the bot's keys, every history export and the secret Constance settings, tokens included; without it none of them can be read (see [Components](components.md)). During a key rotation, keep `waldur.fieldEncryptionKeyFallbacks` too, and restore it with the rest |

### Taking a backup

Tuwunel 1.9 can also back its database up while it runs (`database_backup_path`
and `!admin server backup-database`), but the chart does not configure it, an
admin has to run the command in the admin room, and it leaves media out. A
copy of the volume taken while the homeserver is scaled to zero needs none of
that and includes media. Chat is down while it is taken; Waldur is not. Where
the storage class supports CSI volume snapshots, a `VolumeSnapshot` of the
stopped claim does the same job; otherwise copy the files out through a pod
that mounts the claim:

```bash
kubectl scale --replicas=0 statefulset/matrix-homeserver deployment/waldur-matrix-bot
kubectl wait --for=delete pod/matrix-homeserver-0 --timeout=5m
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: matrix-homeserver-copy
spec:
  restartPolicy: Never
  containers:
    - name: copy
      image: alpine:3
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /var/lib/tuwunel
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-matrix-homeserver-0
EOF
kubectl wait --for=condition=Ready pod/matrix-homeserver-copy --timeout=5m
kubectl exec matrix-homeserver-copy -- tar -C /var/lib/tuwunel -czf - . > tuwunel_data.tar.gz
gzip -t tuwunel_data.tar.gz
kubectl delete pod matrix-homeserver-copy
# Only what a restore needs: the API server refuses to create an object that
# carries a resourceVersion, and a new cluster may use another namespace.
kubectl get secret matrix-appservice-secret -o json |
  jq '{apiVersion, kind, type, data, metadata: {name: .metadata.name, labels: .metadata.labels}}' \
  > matrix-appservice-secret.json
# Waldur's database, while the bot is stopped. With postgresBackup.enabled, run
# the chart's backup CronJob now and wait for it:
kubectl create job --from=cronjob/waldur-db-backup-cronjob waldur-db-backup-matrix
kubectl wait --for=condition=complete job/waldur-db-backup-matrix --timeout=30m
kubectl delete job waldur-db-backup-matrix
# Otherwise dump it yourself, e.g. from the bundled PostgreSQL's pod:
#   kubectl exec <postgres-pod> -- pg_dump -Fc -U waldur waldur > waldur.dump
kubectl scale --replicas=1 statefulset/matrix-homeserver deployment/waldur-matrix-bot
```

The bot is stopped with the homeserver so that the keys in the database backup
match the homeserver's copy. For the same reason the scheduled
`waldur-db-backup-cronjob` runs are no substitute: they run while the bot is up,
so their dumps do not pair with a copy of the volume. Under ArgoCD, pause
automated sync first: self-heal scales both back up.

Keep the files off the cluster, and restrict access to them as to the database:
together they hold every token and, with the homeserver's volume, the keys to
every user's key backup, and so to every encrypted message.

History exports are encrypted and do not compress, so the database dumps grow by
about as much as the exports take up.

LiveKit keeps no state: only its API key and secret matter (the
`matrixChat.livekit.keys` values or their Secret), and these are part of the
release's values or Secrets you already keep. If TURN is on, keep the Secret
named by `matrixChat.livekit.turn.tls.existingSecret` too, or let cert-manager
issue it again. Nothing of a call needs restoring, but calls in progress drop
while the homeserver is stopped, and none can start until it is back: Waldur
checks each caller at the homeserver before it issues a call token.

### Restoring the homeserver

When the claim is lost or damaged, by a failed Tuwunel upgrade for example,
restore it. The StatefulSet adopts an existing claim named
`data-matrix-homeserver-0` instead of creating an empty one, so create the claim
and fill it before the homeserver starts: on an empty volume Tuwunel creates a
new database, and the archive cannot be unpacked over that.

```bash
kubectl scale --replicas=0 statefulset/matrix-homeserver deployment/waldur-matrix-bot
kubectl wait --for=delete pod/matrix-homeserver-0 --timeout=5m
# Only if the old claim still exists. Copy it out first, as above, in case the
# backup turns out to be the wrong one.
kubectl delete pvc data-matrix-homeserver-0
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-matrix-homeserver-0
spec:
  accessModes: ["ReadWriteOnce"]
  # matrixChat.homeserver.persistence.size, and its storageClass if set
  resources:
    requests:
      storage: 10Gi
EOF
```

Start the copy pod from the backup step again, then:

```bash
kubectl wait --for=condition=Ready pod/matrix-homeserver-copy --timeout=5m
kubectl exec -i matrix-homeserver-copy -- tar -C /var/lib/tuwunel -xzf - < tuwunel_data.tar.gz
kubectl delete pod matrix-homeserver-copy
kubectl exec deployment/waldur-mastermind-worker -- waldur shell -c \
  "from django.db import connection; connection.cursor().execute('DELETE FROM matrix_bot.synctokens')"
kubectl scale --replicas=1 statefulset/matrix-homeserver deployment/waldur-matrix-bot
```

The registration comes back with the volume, so the wiring Job changes nothing
on the next sync, unless the tokens were rotated after the backup: then it
replaces the registration, as after a [rotation](#rotating-the-tokens).

Waldur's database is now newer than the homeserver.
[Restoring only the homeserver](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#restoring-only-the-homeserver)
in Waldur's admin guide says what that breaks: deleting `matrix_bot.synctokens`
resets the bot's read position, without which it skips events; new chat
sessions may not reach the bot for a while; users and rooms created after the
backup are missing, which its repair snippet fixes; and members' key backups
roll back, which its last command refills. Run its `waldur shell -c "…"`
commands with `kubectl exec deployment/waldur-mastermind-worker --` in front,
and the repair snippet with
`kubectl exec -i deployment/waldur-mastermind-worker -- waldur shell <<'EOF'`.
Restoring only Waldur's database to an older backup has the reverse effects:
see [Restoring only Waldur's database](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-appservice-setup/#restoring-only-waldurs-database).

### Restoring everything

On a new cluster, or after losing the namespace, restore in this order, so that
nothing starts on an empty volume or mints new tokens:

1. Create the namespace and the Secret from the saved copy. The secrets Job
   then reuses the tokens instead of generating new ones:

   ```bash
   kubectl create namespace <namespace>
   kubectl -n <namespace> create -f matrix-appservice-secret.json
   ```

2. Restore Waldur's database, and set the same `waldur.secretKey` and
   `waldur.fieldEncryptionKey`, and `waldur.fieldEncryptionKeyFallbacks` if a
   key rotation was under way. This order needs the database outside the
   release, as with `externalDB`: the bundled PostgreSQL only exists once the
   chart is installed, and this guide does not cover restoring into it.
3. Create and fill `data-matrix-homeserver-0` as above.
4. `helm install`. The wiring Job finds the appservice already registered and
   changes nothing.

### Losing the setup Secret

If `matrix-appservice-secret` is deleted while the homeserver keeps its data,
put it back before the next sync: the secrets Job would otherwise mint new
tokens that neither the homeserver nor Waldur holds. `helm upgrade` refuses to
render while the `matrix-homeserver` StatefulSet runs and the Secret is
missing. ArgoCD renders without access to the cluster, so the check cannot run
there: pause automated sync until the Secret is back.

Create it from the backup, as in step 1 above. Without a backup, rebuild it
from Waldur's settings, which hold the same tokens. The values go from the API
pod straight into the Secret, never through a command line or a file:

```bash
kubectl -n <namespace> exec deploy/waldur-mastermind-api -- waldur shell -c '
import json
try:
    from waldur_core.configuration import config
except ModuleNotFoundError as e:  # mastermind keeping settings in constance
    if e.name != "waldur_core.configuration":
        raise
    from constance import config
print("SECRET " + json.dumps({
    "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
    "metadata": {"name": "matrix-appservice-secret",
                 "labels": {"app.kubernetes.io/managed-by": "matrix-init"}},
    "stringData": {
        "as_token": config.MATRIX_APPSERVICE_AS_TOKEN,
        "hs_token": config.MATRIX_APPSERVICE_HS_TOKEN,
        "registration_token": config.MATRIX_USER_REGISTRATION_SECRET,
    },
}))
' | sed -n 's/^SECRET //p' | kubectl -n <namespace> create -f -
```

The bootstrap password is lost with the Secret, since Waldur never stores it,
and a new one would not match `@waldur-bootstrap`. Syncs keep working: the
wiring Job only warns that it could not compare the registration. The next
change to the registration, a token rotation say, needs an `admin_token` in the
Secret, as in [Rotating with password login off](#rotating-with-password-login-off).

### Checking a restore

`GET /api/admin/matrix/diagnostics/` (staff) passes the checks it passed before
the restore, `history_exports` among them with no failures. Then send `!help` in
a room: the bot answers.

Where history export is on, download the newest completed export
(`GET /api/matrix/exports/?state=completed`, then
`GET /api/matrix/exports/<uuid>/download/export/`). A `409` means the export
cannot be decrypted, most likely because the restored database does not match
the configured `FIELD_ENCRYPTION_KEY` (or `SECRET_KEY`, while that is unset):
then the recovery keys and the bot's keys cannot be read either.

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
Tuwunel reads `0` as "expire immediately". Waldur also signs out its chat
devices idle for more than 24 hours, when a user starts a session and in a
daily job at 03:45 UTC, so a refresh lifetime longer than a day, or `0`, keeps
an idle drawer's device for at most about two days while the daily job runs:
one that has been idle just under 24 hours at the daily run is left until the
next. The job skips a run when the homeserver does not answer.

Clients that sign in without a refresh token, such as Element with a password,
get non-expiring tokens and are unaffected.

Tuwunel reads its configuration only at startup. The homeserver pod carries a
checksum of the `homeserver` values, so a `helm upgrade` that changes any of
them restarts it. Secrets are not tracked, so that the annotation cannot be
used to test guesses at them: after changing `registrationToken`,
`sso.clientSecret` or a Secret you manage yourself, run
`kubectl rollout restart statefulset/matrix-homeserver`.

## Capacity

Homeport keeps one `/sync` long-poll open on the homeserver for every
signed-in user who is a member of an active room, in every open tab, whether
or not the chat drawer is open: it connects in the background to show the
unread badge. Size the homeserver for those users, not only for the ones
chatting.

**One homeserver supports 1000 concurrent users with 4 CPU cores.** Measured on
a MacBook Pro (Apple M4 Pro, 12 cores, 24 GiB) under Docker Desktop
with 12 CPUs and 7.75 GiB, with Tuwunel v1.9.3 as Docker Compose configures
it, which matches this chart on caches, presence and token lifetimes:

| Concurrent users | CPU limit | p95 delivery | CPU used, cores (average / peak) | Memory |
| --- | --- | --- | --- | --- |
| 500 | 2 | 0.38 s | 0.6 / 2.1 | 250 MiB |
| 1000 | 2 | 71 s, fell behind | 2.0 / 2.2 | 470 MiB |
| 1000 | 4 | 0.41 s | 1.9 / 4.1 | 320 MiB |
| 500 | none | 0.10 s | 0.4 / 1.1 | 270 MiB |
| 1000 | none | 0.14 s | 1.8 / 4.3 | 310 MiB |
| 2000 | none | 1.6 s, p99 5.7 s | 5.4 / 9.3 | 490 MiB |
| 3000 | none | 77 s | 9.5, saturated | 1.1 GiB |

Delivery runs from the start of the send request to the message arriving in
another member's `/sync`. Users and rooms were created by Waldur: rooms of 25
members plus the bot, so Waldur's appservice received the homeserver's
transactions as in production. Each user synced as the drawer does (30 s
long-polls, presence on, access tokens refreshed every 5 minutes) and sent a
message every 5 minutes on average, busier than most project chats; one in ten
posted a read receipt for every message, as a drawer open on the room does.
Each step started with every user loading the page within 30 s.

CPU grows faster than the number of users: from 1000 to 2000 users it tripled.
Idle connections are cheap (1000 users sending nothing took half a core); what
costs is fanning messages and read receipts out to the members of each room.
At 2000 users the page loads at the start saturated nine cores and p99
delivery passed 5 s; at 3000, messages took over a minute.

The figure does not cover:

- Server hardware. It was measured on a laptop, which also ran the rest of the
  Waldur stack and the load generator.
- End-to-end encryption. Messages were plain text of the size of an encrypted
  one. The drawer keeps its keys in memory, so every page load is a new device:
  it uploads its keys, the clients of the other members fetch them, and each
  sender's next message shares its session key with the new device, one
  to-device message per device in the room. A device signed out, by Waldur's
  daily prune too, makes senders share a new key with every device. Each page
  load also rehydrates the user's dehydrated device, which collects the room
  keys sent while no drawer was open and is then replaced by a fresh one, and
  restores the user's key backup in the background; both grow with the history
  the user can read. The dehydrated device is one more device per user that
  senders share keys with. None of this was simulated, so take the figure as an
  upper bound.
- Other traffic. One room per user, no typing notifications, media, calls or
  federation, and a database with little history. The ingress was not in the
  path. Calls add nothing to size for here: their media is encrypted end to end
  in the browsers and LiveKit only forwards the encrypted frames.

Before going past 1000 concurrent users, measure on your own hardware, on a
test deployment rather than production, with load shaped like the above:
users and rooms created through Waldur, so that its appservice is in the path,
each user syncing as the drawer does, and every user loading the page at the
start.

### Homeserver resources

`matrixChat.homeserver.resources` defaults to `{}`, which does not fit
production. With no requests the pod is BestEffort: the scheduler reserves
nothing for it, and the kubelet evicts it first when its node runs short of
memory, which drops every chat connection at once. For up to 1000 concurrent
users:

```yaml
matrixChat:
  homeserver:
    resources:
      requests:
        cpu: "2"
        memory: 1Gi
      limits:
        cpu: "4"
        # About 1 GiB plus 0.2 GiB per CPU core of the node, see below.
        memory: 4Gi
```

- **CPU.** At 1000 users the homeserver used under 2 cores on average, but page
  loads and bursts of messages took it to 4. Leave the limit off or set it to at
  least 4: under a limit of 2 the same load fell behind and never caught up.
- **Memory.** Tuwunel sizes its caches from the CPU cores of the node, not from
  a CPU limit: its defaults scale them with the core count, and on the 12-core
  machine above they could grow to about 2.4 GiB, under a 2-core limit as well.
  They fill as the history grows, not with the number of users, and held under
  100 MiB here. A memory limit below them gets the pod OOM-killed once the
  database is large enough, so plan on roughly 1 GiB plus 0.2 GiB per core of
  the nodes it may run on, or leave the limit unset. The chart has no setting
  for Tuwunel's cache sizes.

### Bot resources

The bot (`matrixChat.bot`) decrypts every message in every Waldur room, makes
every history export, up to three at a time, and writes rooms' earlier keys into
new members' key backups. The chart's defaults are requests of `100m` CPU and
`300Mi` memory, limits of `500m` and `600Mi`. An export keeps a few MiB of
working files in memory and spills the rest, encrypted, to temporary files in
`/tmp`; with `MATRIX_EXPORT_MEDIA` on, each export holds up to 200 MB of media,
in files of up to 50 MB. One attachment at a time is held in memory, and saving
an export reads its files whole, so with media export on raise the memory limit
by a few hundred MiB if the bot is OOM-killed while exporting. Exports running
side by side take turns at both, so three exports need no more memory than one.

### Database growth

With `MATRIX_HISTORY_EXPORT_ENABLED` on, a task at 02:00 every night queues a
full-history export of every active room, and with `MATRIX_EXPORT_MEDIA` on each
one carries its media too, up to 200 MB. Exports are stored, encrypted, in
Waldur's database and kept for `MATRIX_HISTORY_EXPORT_RETENTION_DAYS`, 90 by
default, along with each room's newest completed export whatever its age. Plan
PostgreSQL's volume and its backups for about 90 daily copies of every active
room's history and media; encrypted files do not compress.

### One replica

Tuwunel is one process with an embedded RocksDB database on a ReadWriteOnce
volume, so the chart runs it as a StatefulSet of exactly one replica. It scales
up, not out: a second replica cannot share the load. Scaling up has diminishing
returns, since each added core buys fewer users than the last: at the traffic
above, 2000 concurrent users was already the knee with 12 cores.

## Single sign-on for Matrix clients

With Waldur's `MATRIX_EXTERNAL_LOGIN_METHOD` set to `oidc`, users sign in to
Element or another Matrix client through the same identity provider (IdP) as
Waldur, into the account Waldur provisioned for them.
[Single sign-on for Matrix clients](https://docs.waldur.com/latest/developer-guide/admin-guide/matrix-sso/)
explains how the accounts line up and why the homeserver is configured this
way; this section covers the chart.

Waldur needs `MATRIX_EXTERNAL_LOGIN_METHOD` set to `oidc`, and
`MATRIX_SSO_REGISTRATION_METHOD` set to the name in Waldur of the identity
provider the homeserver signs in through (`keycloak`, say). Waldur gives a
Matrix account only to users who signed in to Waldur through that provider, so
while it is blank nobody gets one. With `matrixChat.setup` on (the default),
set `sso.waldurRegistrationMethod` and the wiring Job seeds both on every sync;
the chart refuses to render SSO without it. With setup off, set them yourself:

```yaml
waldur:
  settingsOverrides:
    MATRIX_EXTERNAL_LOGIN_METHOD: oidc
    MATRIX_SSO_REGISTRATION_METHOD: keycloak
```

Then configure the homeserver:

```yaml
matrixChat:
  homeserver:
    allowRegistration: false
    loginWithPassword: false
    sso:
      enabled: true
      brand: "keycloak"
      name: "Example SSO"
      issuerUrl: "https://keycloak.example.org/realms/waldur"
      clientId: "matrix-homeserver"
      clientSecretExistingSecret:
        name: "matrix-sso"
        key: "client_secret"
      waldurRegistrationMethod: "keycloak"
      forbiddenUsernames:
        - "^admin$"
```

Register `matrix-homeserver` at the IdP with the redirect URI
`https://<serverName>/_matrix/client/unstable/login/sso/callback/matrix-homeserver`.
The client secret reaches the homeserver as a file from a Secret (the chart's
own `matrix-homeserver-sso-secret` when `sso.clientSecret` is set), never
through the ConfigMap. After changing a client secret, run
`kubectl rollout restart statefulset/matrix-homeserver`; changes to the other
chart values restart it on their own. The chart refuses to render SSO without
`issuerUrl`, `clientId` and a client secret, or unless `apiScheme` is `https`:
Tuwunel's SSO cookie is `Secure`.

The chart also refuses SSO together with `allowRegistration: true`. A trusted
provider signs a user in to any existing account named like their claim, so
anyone holding the registration token could register `@bob` first and receive
bob's SSO login. Waldur provisions accounts through its appservice, which works
with registration closed; create any homeserver admin before closing it.

The defaults make SSO sign in to the account Waldur provisioned, or refuse:

| Value | Default | Tuwunel key and chart checks |
| --- | --- | --- |
| `sso.brand`, `sso.name` | `keycloak`, `Single sign-on` | `brand`, the IdP software, and `name`, the label on the clients' sign-in button. |
| `sso.userIdClaims` | `["sub"]` | `userid_claims`. A non-empty list of `sub`, `preferred_username`, `username`, `nickname`, `email` or `login`; the chart refuses anything else. Must be the claim Waldur's identity provider uses as `user_claim`, with its `user_field` left at `username` and `MATRIX_USER_ID_FORMAT=username`. |
| `sso.allowEmailClaim` | `false` | Opt-in for `email` in `userIdClaims`, which the chart refuses otherwise: Tuwunel uses only the local part of the address, so `alice@a.org` and `alice@b.org` sign in to the same account. Set `true` only if the IdP issues addresses of a single domain. |
| `sso.waldurRegistrationMethod` | `""` | Not a Tuwunel key: Waldur's `MATRIX_SSO_REGISTRATION_METHOD`, the name in Waldur of this identity provider. With `matrixChat.setup` on, the wiring Job seeds it and `MATRIX_EXTERNAL_LOGIN_METHOD: oidc`, and the chart refuses SSO without it. |
| `sso.trusted` | `true` | `trusted`. Signs in to any existing account named like the claim, so keep `sub` unless the IdP controls usernames. With `false`, Tuwunel refuses every account Waldur provisioned. |
| `sso.registration` | `false` | `registration`. SSO creates no accounts; it only signs in to existing ones. With `trusted`, the chart refuses `true` unless `sso.allowRegistrationWhenTrusted` is also `true`: SSO would create an account before Waldur provisions it, and a trusted provider then signs anyone whose claim matches into it. |
| `sso.forbiddenUsernames` | `[]` | `forbidden_usernames`: anchored patterns SSO never signs in to and Tuwunel refuses to register, so create an admin before you list it. The chart always puts the bot's localpart and `waldur-bootstrap`, reserved for the bootstrap admin that automatic registration creates, ahead of the list, so list only the other homeserver admins, such as `admin` above. The bot's localpart is `setup.botLocalpart`, or with setup off `MATRIX_APPSERVICE_SENDER_LOCALPART` from `waldur.settingsOverrides` where that is set; if you changed it in Waldur's settings instead, list it here too. |
| `loginWithPassword` | `true` | `login_with_password`. Set `false` with SSO so clients show no password form. Waldur's drawer is unaffected, but an admin created with a password can then no longer sign in to a client either, so re-registering the appservice after a token rotation needs a homeserver admin's access token, or `true` again for the rotation. |

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
for what that costs. The registration step makes it one, on every sync with
`registerAppservice` on, and Diagnostics shows the result as **Bot is a
homeserver admin**. If it could not, the wiring Job's log says why; add an
`admin_token` to the Secret for one sync, as in
[Rotating with password login off](#rotating-with-password-login-off), and it
tries again.

## Runtime steps, and what now handles them

Four steps used to be manual, and all four failed silently when skipped. With
`setup.enabled` the chart handles all four.

1. **Backend token match** — handled. Both sides are given the same generated
   value; there is no `homeserver.registrationToken` to keep in sync any more,
   and setting one while `setup.enabled` is true is a render error rather than a
   value that is quietly ignored.
2. **Appservice registration** — handled by
   `matrixChat.setup.registerAppservice` (default on). The chart registers the
   appservice through Tuwunel's `!admin appservices register` admin-room
   command; Tuwunel can also read registrations from its config file, which
   the chart does not use. The wiring Job drives that command
   through the mastermind image's `register_matrix_appservice`, as a bootstrap
   admin it creates itself.

   On a new homeserver the command creates `@waldur-bootstrap` through the
   shared-secret registration API, with admin rights and `bootstrap_password`
   as its password. The chart sets the homeserver's
   `registration_shared_secret` to the registration token. The ingress routes
   no `/_synapse` path, but any pod in the cluster can reach the API on the
   homeserver's Service: `matrixChat.networkPolicy` is off by default, and when
   on it admits that port from anywhere. Using the API still takes the
   registration token, an admin's access token, or the `as_token`, which
   reaches it as the bot once the bot is a homeserver admin. That first
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
   `MATRIX_HOMESERVER_PUBLIC_URL` with `<apiScheme>://<serverName>`. Calls
   therefore do not depend on pods reaching the ingress's public address.

   These in-cluster calls are plain HTTP, as are the homeserver's calls to
   Waldur (`http://waldur-mastermind-api.<namespace>.svc`) and Waldur's to the
   bundled LiveKit. They carry the appservice tokens, the passwords and tokens
   Waldur sets or mints for users, and LiveKit room-admin tokens, readable to
   anything that can see traffic inside the cluster.

## The Matrix bot

`matrixChat.bot` deploys mastermind's `matrix_bot` command, Waldur's member of
every Waldur room. It runs on a Matrix device of its own and holds that
device's keys. Every Waldur room is encrypted, so it is the only process that
can post into them: every message Waldur sends as the bot (role, order and
staff notices, command replies) waits in Waldur's database until the bot posts
it, and while the bot is not running, they wait. Clients share their room keys
with its device as with any member's, so it decrypts every message in those
rooms, not only the commands sent to it.

The bot also makes every history export and writes rooms' earlier keys into
new members' key backups, so that they can read what was said before they
joined. While it is down, exports stay `pending` and are made once it starts,
and disabling a room with `MATRIX_HISTORY_EXPORT_ENABLED` on cannot finish: the
room is not archived until its history is exported, so it goes to `error` at
once when the bot is not running, or after 15 minutes when the bot does not
finish the export in time. Disable it again once the bot runs.

- **Exactly one replica.** The bot holds a lease in Waldur's database, and a
  second one refuses to start while the first holds it, so the Deployment uses
  the `Recreate` strategy: the old pod releases the lease before the new one
  starts.
- **No volume.** Its keys live in Waldur's database, in a `matrix_bot`
  schema, pickled under a key stored encrypted with `FIELD_ENCRYPTION_KEY`, or
  with a key derived from `SECRET_KEY` while that is unset (the chart's
  default). Database backups carry them, and losing that key makes the store unreadable:
  the bot then refuses to start rather than reset its identity. Exports do
  spool encrypted temporary files to the container's `/tmp`, up to a few
  hundred MB each with media export on, which counts against the pod's
  ephemeral storage.
- It needs the appservice registered (step 2 of
  [Runtime steps](#runtime-steps-and-what-now-handles-them)) and reaches the homeserver
  at `MATRIX_HOMESERVER_URL`, like the API.
- **Restoring a database elsewhere** (a staging copy of production, say) copies
  the bot's identity with it. Disable `matrixChat.bot` there, or drop the copy's
  `matrix_bot` schema and `matrix_chat_matrixbotidentity` rows, before the bot
  starts: otherwise a second bot runs as the same device, can read the
  original's rooms, and corrupts both bots' sessions. A copy that keeps the
  same `FIELD_ENCRYPTION_KEY` also yields every user's escrowed recovery key and
  every history export, so treat it as you would production.

## Monitoring

The metrics exporter (`waldur.metricsExporter`) calls Waldur's Matrix
diagnostics, `GET /api/admin/matrix/diagnostics/`, about every two minutes
and publishes:

| Metric | Labels | Value |
| --- | --- | --- |
| `waldur_matrix_diagnostics_up` | | `1` if the last diagnostics call succeeded, `0` if it failed |
| `waldur_matrix_check_passed` | `check` | `1` if the diagnostics check passed, `0` if not, e.g. `homeserver_reachable`, `bot_running`, `bot_whoami`, `appservice_ping` |
| `waldur_matrix_rooms` | `state` | Rooms per state: `creating`, `active`, `disabling`, `archived`, `error` |

The exporter calls the endpoint with `waldur.supportToken`, which must belong
to a support or staff user. If every call gets `403`, the token belongs to
neither, and `waldur_matrix_diagnostics_up` stays `0`.

### Scraping the exporter

A Prometheus that scrapes annotated Services finds the exporter through its
`prometheus.io/scrape: "true"` annotation
(`waldur.metricsExporter.includeAnnotations`, on by default). The Prometheus
Operator ignores those annotations; for it, turn on the ServiceMonitor below.

### Alert rules

The chart ships the alert rules as a `PrometheusRule`, off by default:

```yaml
waldur:
  supportToken: <API token of a support or staff user>
  metricsExporter:
    enabled: true
    serviceMonitor:
      enabled: true
      labels:
        release: kube-prometheus-stack   # what your Prometheus selects by
matrixChat:
  prometheusRule:
    enabled: true
    labels:
      release: kube-prometheus-stack
```

Both objects need the Prometheus Operator's CRDs: the chart refuses to render
them on a cluster without the CRDs, and refuses the rules without the
exporter. `helm template` needs
`--api-versions monitoring.coreos.com/v1/ServiceMonitor --api-versions monitoring.coreos.com/v1/PrometheusRule`
to render them. kube-prometheus-stack picks up only ServiceMonitors and rules
labelled `release: <its release name>`; others are applied and then ignored,
without an error anywhere.

Without the Prometheus Operator, load the same rules into your Prometheus from
[`waldur/files/matrix-chat-alerts.yaml`](https://github.com/waldur/waldur-helm/blob/master/waldur/files/matrix-chat-alerts.yaml),
or copy them from the
[Docker Compose guide](https://docs.waldur.com/latest/admin-guide/deployment/docker-compose/matrix-chat-add-on/#monitoring).
The rules match the metrics of every Waldur the Prometheus scrapes, so with
several releases on one Prometheus, enable them in one. A Waldur that never
had Matrix chat raises no alert among them: its diagnostics report that no
homeserver URL is set, and the alerts stay quiet where that is so. One where
chat was switched off but `MATRIX_HOMESERVER_URL` is still set keeps raising
the homeserver and bot alerts. The other side of it: if that setting is
emptied on a Waldur that has chat, its four check alerts fall silent.
`WaldurMatrixMetricsMissing` fires only when no exporter at all publishes
Matrix metrics, so with several it does not notice one of them going away.

| Alert | Fires when | Severity | First thing to check |
| --- | --- | --- | --- |
| `WaldurMatrixMetricsMissing` | No `waldur_matrix_diagnostics_up` series for 15 minutes | warning | The exporter pod runs a version with Matrix metrics, and Prometheus lists it as a target: a ServiceMonitor without the right labels is ignored. |
| `WaldurMatrixDiagnosticsDown` | The diagnostics call failed for 10 minutes | warning | The exporter's log. `403` means `waldur.supportToken` belongs to neither a support nor a staff user; anything else, the `waldur-mastermind-api` log. |
| `WaldurMatrixHomeserverUnreachable` | `homeserver_reachable` failed for 5 minutes while a homeserver URL is set | critical | `kubectl logs matrix-homeserver-0`. A homeserver that is up but not answering after an image change is migrating its database: do not restart it, see [Upgrading](#upgrading). |
| `WaldurMatrixBotNotRunning` | `bot_running` failed for 10 minutes while a homeserver URL is set | warning | `kubectl logs deployment/waldur-matrix-bot`, and that `matrixChat.bot.enabled` is on. |
| `WaldurMatrixBotSignInFailing` | `bot_whoami` failed for 10 minutes while the homeserver is reachable | warning | The appservice registration: the `matrix-init-wire` Job's log, and [Rotating the tokens](#rotating-the-tokens) if the tokens changed. |
| `WaldurMatrixAppservicePingFailing` | `appservice_ping` failed for 10 minutes while `bot_whoami` passes | warning | That the homeserver can reach `waldur-mastermind-api` at the registered appservice URL: the API pods and, if on, the NetworkPolicies. |
| `WaldurMatrixRoomsErred` | At least one room in the `error` state for 30 minutes | warning | `GET /api/matrix/rooms/?state=error` lists them with their `error_message`. Fix the cause, then retry each room as staff with `POST /api/matrix/rooms/<uuid>/retry/`. |

When the homeserver is unreachable, the bot's whoami and the appservice ping
fail with it, so their alerts stay quiet while
`WaldurMatrixHomeserverUnreachable` fires. Waldur skips the ping when whoami
fails, so the ping alert also stays quiet while `WaldurMatrixBotSignInFailing`
fires.

The alerts read the `:last20m` series the same rules record, which keep each
check's and room count's last value for 20 minutes, so a brief exporter or
Prometheus restart neither resolves a real alert nor starts its timer over.
They are recorded per Waldur, not per scrape target. On Kubernetes, where a
target has a `namespace` label, a Waldur is a namespace and job, so an
exporter pod that is replaced continues the series. Elsewhere each target is
a Waldur. On a Prometheus that holds several clusters whose Waldurs share a
namespace name and job, the rules take those Waldurs for one. Leave
`matrixChat.prometheusRule` off there and load a copy of the rules file with
the cluster's label added to the `by` of the two `:per_waldur` rules.

The thresholds follow the exporter's two-minute refresh: 5 minutes is two or
three failed refreshes in a row and 10 minutes about five, which rides out a
pod restart.

Waldur never retries an erred room on its own, so `WaldurMatrixRoomsErred`
keeps firing until staff retry the rooms; the 30 minutes give staff already
handling an outage time to do that first.

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
symmetric NAT and restrictive networks. That holds only on 443, the default:
those firewalls allow nothing else, so keep it. Plain TURN/UDP is
intentionally not exposed — relayed media always rides TLS.

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
- **The call-encryption worker.** Calls encrypt their media in a Web Worker
  that homeport serves from its own origin (`/assets/e2eeWorker-*.js`), so
  `script-src 'self'` already covers it and the chart sets no `worker-src`. A
  policy of your own that sets `worker-src` must include `'self'`, or calls in
  encrypted rooms fail.
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
apiScheme: https                                # the chart refuses calls over http
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
media plane are the external operator's responsibility. The chart adds the
`publicUrl` origin to the homeport Content-Security-Policy `connect-src` on every
ingress variant, so the browser is allowed to open the signalling websocket to it;
nothing needs configuring for that.
