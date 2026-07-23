# Matrix chat (homeserver + LiveKit calls)

The chart can deploy the Matrix chat infrastructure: a Tuwunel homeserver, a
LiveKit media SFU, and lk-jwt-service (required for voice/video calls).

## Enabling

```yaml
matrixChat:
  enabled: true
  networkPolicy:
    enabled: true   # ships the livekit/lk-jwt/homeserver NetworkPolicies; independent of the chart-wide networkPolicy.enabled
  homeserver:
    enabled: true
    serverName: matrix.example.org   # immutable; baked into every user/room ID
    registrationToken: <secret>      # MUST equal the backend MATRIX_USER_REGISTRATION_SECRET
    livekitServiceUrl: https://matrix.example.org   # public lk-jwt base, advertised to clients
  livekit:
    enabled: true
    publicUrl: wss://matrix.example.org
    keys:
      apiKey: <key>
      apiSecret: <secret>
    rtc:
      nodeIp: <livekit-rtc LoadBalancer external IP>   # else calls connect with no media
  lkJwt:
    enabled: true
```

Both secret groups (`livekit.keys` — `apiKey` + `apiSecret` — and
`homeserver.registrationToken`) support `existingSecret` for external secret
managers.

## Image pinning

Images are pinned to specific versions by default — never `latest`:

- **homeserver** — `ghcr.io/matrix-construct/tuwunel`, pinned to the latest bare
  multiarch tag. Set `homeserver.imageDigest` to pin immutably by digest.
- **livekit** — `livekit/livekit-server`, pinned by tag; `livekit.imageDigest`
  available. Pulled from `livekit.imageRegistry` (`docker.io` by default) — its
  own key, **not** `global.imageRegistry`, so pointing `global` at a private
  mirror doesn't rewrite LiveKit to a registry that has no such image. Override
  `livekit.imageRegistry` if you mirror it.
- **lk-jwt** — `ghcr.io/element-hq/lk-jwt-service` publishes **no semver tags**
  (only `latest` and `sha-<commit>`), so it is pinned **by digest**
  (`lkJwt.imageDigest`). Update the digest to upgrade, or set `lkJwt.imageTag` to
  a `sha-<commit>` tag and clear the digest.

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
4. **lk-jwt → homeserver reachability.** lk-jwt-service verifies each caller's
   Matrix OpenID token over federation against `https://<serverName>`, which
   resolves to the *public* ingress address. The cluster must therefore be able
   to resolve **and reach** `serverName` from inside a pod — i.e. either the
   external LoadBalancer supports hairpin (in-cluster traffic to its own public
   IP loops back through the ingress) or split-horizon DNS points `serverName` at
   the ingress internally. If neither holds, chat works but **calls fail** at the
   token-exchange step. (`lkJwt.insecureSkipVerifyTls` only relaxes the cert
   check — it does not fix reachability.)

## Open-registration guard

If `homeserver.allowRegistration` is `true` but no `registrationToken` (or
`registrationTokenExistingSecret`) is set, the chart **refuses to render** — this
prevents shipping an open, abusable homeserver. Provide a token, or set
`allowRegistration: false`.

The chart fails the render in two more cases, to turn silent runtime breakage
into an obvious config error:

- `livekit.enabled` with **no credentials** (neither `livekit.keys.apiKey` +
  `apiSecret` nor `livekit.keys.existingSecret.name`) — otherwise livekit-server
  starts with no signing key and lk-jwt references a Secret that doesn't exist.
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
- **NetworkPolicies.** When `matrixChat.networkPolicy.enabled` is `true`, the chart
  adds a policy per pod. This gate is independent of the chart-wide
  `networkPolicy.enabled` (which only covers the homeport/mastermind-api
  policies) — set it to ship the matrix/livekit policies without opting the
  rest of the stack into NetworkPolicy. The livekit policy accepts media from
  **anywhere** (external WebRTC). The homeserver and lk-jwt policies accept
  HTTP only from **in-namespace** pods (i.e. the ingress controller, same
  assumption as the homeport/API policies). Egress is left open on all three —
  federation, OpenID verification, and `/twirp` room creation all need
  outbound reach to `serverName`.

## Using an external LiveKit

You can run the Matrix calling stack against an **operator-managed LiveKit SFU**
instead of the bundled `livekit-server` — the same bring-your-own-backend pattern
the chart offers for PostgreSQL. Tuwunnel and lk-jwt-service stay bundled, because
lk-jwt is tied to *this* homeserver's federation identity; only the SFU is external.

Why it works: the browser reaches LiveKit client-side via the URL lk-jwt returns
(`livekit.publicUrl`), and lk-jwt signs call tokens with an API key/secret it shares
with the LiveKit server. Point both at your external instance and the bundled SFU
is never needed. Mastermind never talks to LiveKit, so there is no backend change.

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
  lkJwt:
    enabled: true                               # keep the token broker
  homeserver:
    enabled: true                               # Tuwunnel stays bundled
    serverName: matrix.example.org
    livekitServiceUrl: "https://matrix.example.org/sfu"
```

The `existingSecret` must hold the **same** API key and secret configured on your
external LiveKit, under the keys named above. If you omit `existingSecret.name`
while `livekit.enabled=false`, the chart refuses to render — the bundled
`livekit-secret` only exists when the bundled server is deployed, so lk-jwt would
otherwise reference a non-existent Secret and crashloop.

With `livekit.enabled=false` the chart drops the in-cluster LiveKit Service, its
`config.yaml`, network policy, RTC LoadBalancer, and the `/rtc` + `/twirp` ingress
routes. The browser connects straight to `publicUrl`, so reachability, TLS, and the
media plane are the external operator's responsibility.
