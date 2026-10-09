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
    registrationToken: <secret>      # MUST equal the backend MATRIX_USER_REGISTRATION_SECRET
  livekit:
    enabled: true
    publicUrl: wss://matrix.example.org   # calls are offered only when this is set
    keys:
      apiKey: <key>
      apiSecret: <secret>
    rtc:
      nodeIp: <livekit-rtc LoadBalancer external IP>   # else calls connect with no media
```

Both secret groups (`livekit.keys` — `apiKey` + `apiSecret` — and
`homeserver.registrationToken`) support `existingSecret` for external secret
managers.

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
2. Bump `imageTag` and `helm upgrade`.
3. Let the first boot finish. A pod that is slow to become ready is migrating,
   not hung. The chart's `startupProbe` keeps liveness off for up to six hours
   so Kubernetes does not kill it mid-migration, which corrupts the database.
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
- No fixed release yet: `matrixChat.enabled=false` removes the homeserver, its
  ingress and the chat UI. The PVC and its history are kept.

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
- It needs the appservice registered (step 2 below) and reaches the homeserver
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

- **Settings.** The init-whitelabeling job seeds `MATRIX_LIVEKIT_PUBLIC_URL`
  (`livekit.publicUrl`), `MATRIX_LIVEKIT_URL` (the bundled LiveKit's in-cluster
  Service, or an external LiveKit's public URL as `https://`), and
  `MATRIX_LIVEKIT_KEY` / `MATRIX_LIVEKIT_SECRET` from the LiveKit Secret. They
  are overwritten on every `helm upgrade`, like the other seeded settings; a
  `waldur.settingsOverrides` entry for either URL takes precedence. The
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

## Required runtime steps (not automated by the chart)

1. **Backend token match.** `homeserver.registrationToken` must equal the
   backend's `MATRIX_USER_REGISTRATION_SECRET` (set via the Waldur Setup wizard,
   persisted in Constance — not a Helm value).
2. **Appservice registration.** Tuwunel registers appservices at runtime via the
   `!admin appservices register` admin-room command, not from config. This can be
   done interactively from a Matrix client or automated — see the
   [Matrix chat add-on docs](https://docs.waldur.com/latest/admin-guide/deployment/docker-compose/matrix-chat-add-on/)
   for the procedure. Re-running Setup rotates the tokens — re-register if you do.
3. **LoadBalancer IP.** After the `livekit-rtc` Service gets its external IP, set
   `livekit.rtc.nodeIp` to it so LiveKit advertises a reachable ICE candidate.
4. **Homeserver URL.** `MATRIX_HOMESERVER_URL` is where Waldur calls the
   homeserver, for chat and to verify call tokens. Prefer the in-cluster
   address (e.g. `http://matrix-homeserver.<namespace>.svc:6167`); the public
   `https://<serverName>` works only if pods can reach the ingress's public
   address.

## Open-registration guard

If `homeserver.allowRegistration` is `true` but no `registrationToken` (or
`registrationTokenExistingSecret`) is set, the chart **refuses to render** — this
prevents shipping an open, abusable homeserver. Provide a token, or set
`allowRegistration: false`.

The chart fails the render in two more cases, to turn silent runtime breakage
into an obvious config error:

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
