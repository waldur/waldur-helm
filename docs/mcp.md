# Remote MCP server

AI agent clients connect to `/mcp` on the API host over the Model Context
Protocol and read Waldur data as the signed-in user. They sign in with OAuth,
or with a personal access token. A separate `waldur-mastermind-mcp`
Deployment runs `waldur mcp_server`; the API serves the OAuth endpoints.

## Enabling

```yaml
waldur:
  mcp:
    enabled: true
    replicas: 1
    # Threads that run database calls, each holding one Postgres connection.
    dbThreads: 4
    resources: {}
```

Then turn on the `MCP_ENABLED` setting, in the admin UI or through
`waldur.settingsOverrides`. Until then, `/mcp` and the OAuth endpoints answer
404.

The chart then:

- runs `waldur mcp_server` pods and a `waldur-mastermind-mcp` Service. The
  server is stateless, so replicas need no session affinity;
- routes these paths on the API hosts (`apiHostname`, or `localApiHostname`,
  and `apiExtraHosts`), through an Ingress or an HTTPRoute:

  | Path | Served by |
  |------|-----------|
  | `/mcp` | MCP pods |
  | `/.well-known/oauth-protected-resource` | MCP pods |
  | `/.well-known/oauth-authorization-server` | API |
  | `/oauth/authorize`, `/oauth/token`, `/oauth/revoke_token`, `/oauth/register` | API |

  `/oauth/consent` is not among them: it's the portal page where users
  approve a client, and the portal often shares the API's host;
- seeds `MCP_RESOURCE_URLS` with `<apiScheme>://<host>/mcp` for
  `apiHostname` and then each of `apiExtraHosts`, space-separated. Clients
  reject resource metadata that names another host than the one they
  connected to. While the setting is empty, Waldur issues no OAuth token and
  clients can only use personal access tokens. To set it yourself, put the
  whole value in `waldur.settingsOverrides`, which then wins. Like every
  seeded setting, it is applied by the init-whitelabeling hook, which runs
  only while `waldur.initdbEnabled` is true; otherwise set it in the admin
  UI;
- adds a NetworkPolicy for the MCP pods when `networkPolicy.enabled` is set.
  The API pods already allow outbound HTTPS, which they need to fetch the
  metadata of clients that identify themselves by URL.

## What the pods get

The MCP pods face the internet, so they get less than the API pods:

- of the mounted files, only the settings file (`override.conf.py`), none of
  the SSH keys, kubeconfig or other files the API pods mount;
- of the environment variables the chart gives mastermind pods, only the
  database, the RabbitMQ broker, the Django and field encryption keys, Sentry
  and the outbound proxy. Not the mail, LDAP, eduTEAMS or DataCite
  credentials. The list is an allowlist (`waldur.mcp.credentials` in
  `_helpers.tpl`), so a variable the chart adds later stays out until it is
  named there;
- no service account token, no Linux capabilities, no privilege escalation, a
  read-only root filesystem and the `RuntimeDefault` seccomp profile. The
  server can write only to `/tmp`. The `wait-for-migrations` init container
  gets the same restrictions and variables, and no writable path.

Every mastermind pod mounts the same settings file, so secrets the chart
writes into it reach the MCP pods too:

- `waldur.ldap.password` and the eduTEAMS `clientSecret`, `refreshToken` and
  `sshApiPassword`. Set them through `waldur.ldap.passwordExistingSecret` and
  `waldur.remoteEduteams.existingSecret` instead, and they stay out;
- the `tokenSecret` of `customInvitations`, `serviceAccountApiIntegration`
  and `courseAccountApiIntegration`, which have no Secret option.

The pods run as the image's `waldur` user. The chart sets no `runAsNonRoot`:
the image names that user rather than a UID, which the kubelet can't check.

## Database connections

Each MCP pod holds up to `dbThreads` Postgres connections.
`replicas × dbThreads` counts against Postgres `max_connections`, on top of
the API and Celery pods.

## CORS

Browser-based MCP clients call these routes from their own origin. Clients
that call `/mcp` from a server or a desktop app don't need CORS.

- **OAuth endpoints.** Waldur answers them with
  `Access-Control-Allow-Origin: *` and no credentials, and that answer has to
  reach the browser. On nginx they are on their own Ingress,
  `mcp-oauth-ingress`, without `enable-cors`: ingress-nginx would answer
  preflights itself and swap `*` for the caller's origin plus
  `Allow-Credentials`. Traefik's `api-cors` middleware and HAProxy's
  `cors-enable` answer with `*` and no credentials too, and allow the
  `MCP-Protocol-Version` header.
- **`/mcp` and its metadata.** The MCP server answers CORS itself, with
  `Access-Control-Allow-Origin: *`, no credentials, any request header, and
  `WWW-Authenticate` exposed so that a browser can read the 401 challenge.
  `mcp-ingress` adds no CORS of its own on any controller: on Traefik it goes
  through `mcp-chain`, which is `api-chain` without `api-cors`. Images up to
  8.1.5-rc.2 send no CORS there, so a client that calls `/mcp` from a web
  page needs a later mastermind image.
- **Gateway API.** The chart adds no CORS. Don't add a CORS policy to
  `mcp-httproute` or `mcp-oauth-httproute` in `gatewayAPI.extraPolicies`: it
  would replace Waldur's own answer.

## IP allow-listing

On the Ingress path, `ingress.whitelistSourceRange` covers the MCP routes as
it covers the API. On the Gateway API path, an allow-list policy in
`gatewayAPI.extraPolicies` covers only the routes it targets: add
`mcp-httproute` and `mcp-oauth-httproute` next to `api-httproute`, or `/mcp`
and the OAuth endpoints stay open to everyone.

## Behind more than one proxy

The throttle on new OAuth clients keys on an `X-Forwarded-For` entry, as the
limit on failed passwords does. `waldur.trustedProxyCount` sets both; see
[IP whitelisting](ip-whitelisting.md).

## Checking it

With `MCP_ENABLED` on, the resource metadata names the seeded URL:

```bash
curl -s https://<apiHostname>/.well-known/oauth-protected-resource/mcp
# {"resource": "https://<apiHostname>/mcp", "authorization_servers": [...], ...}
```

A request to `/mcp` without a token answers 401, with a `WWW-Authenticate`
header that points at that metadata.
