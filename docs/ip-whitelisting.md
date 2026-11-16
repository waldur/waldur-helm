# Limiting network access to Mastermind APIs

Waldur Helm allows limiting network access to Mastermind API endpoints - i.e. `/api/`, `/api-auth/`, `/scim/`, `/admin/` - based on whitelisting the subnets from where access is allowed. To define a list of allowed subnets in CIDR format for the all the API endpoint, please use `ingress.whitelistSourceRange` option in `values.yaml`. Example:

```yaml
...
ingress:
  whitelistSourceRange: '192.168.22.0/24'
...
```

Given this value, only IPs from `192.168.22.0/24` subnet are able to access Waldur Mastermind APIs.
With the [remote MCP server](mcp.md) enabled, it also covers `/mcp` and the OAuth endpoints.

In case you want to limit access to `/api/admin/` endpoint specifically, there is another option called `ingress.whitelistSourceRangeAdmin`:

```yaml
...
ingress:
  whitelistSourceRangeAdmin: '192.168.22.1/32'
...
```

This will limit access to the admin endpoint only for `192.168.22.1` IP. **Note: The `whitelistSourceRangeAdmin` option takes precedence over `whitelistSourceRange`.**

In case of multiple subnets/IPs, comma separated list can be used as a value. E.g.: `192.168.22.1/32,192.168.21.0/24`. This works for both options.

**Note**: this page covers the Ingress path. [Gateway API](gateway-api.md) has no standard
resource for IP allow-listing -- see the `extraPolicies` section of that doc for the
implementation-specific equivalent (e.g. Envoy Gateway's `SecurityPolicy`). A policy covers
only the routes it targets, so with the remote MCP server it must also target
`mcp-httproute` and `mcp-oauth-httproute`.

## Client addresses behind a load balancer

Mastermind reads the client address from `X-Forwarded-For` in two ways:

- The limit on failed passwords per address, the address the sign-in
  lockout records, and the throttle on new OAuth clients of the
  [remote MCP server](mcp.md) take the entry `waldur.trustedProxyCount`
  places from the right (mastermind's default is 1).

- Personal access token network restrictions (`allowed_networks`), organization
  access subnets, resource network rules and the event log take the **first**
  entry. If the ingress passes on a header the client sent, these see whatever
  the client wrote there.

By default ingress-nginx ignores an incoming `X-Forwarded-For` and sends the
address it received the request from, so behind an HTTP load balancer every
client gets the balancer's address: failed passwords from all clients count
against one address, and once they reach the limit, password sign-in is
refused for everyone.

### Recommended: let the ingress resolve the address

Have the ingress controller take the client address from the balancer's header
and pass on only that. With ingress-nginx, in the controller's ConfigMap:

```yaml
use-forwarded-headers: "true"
proxy-real-ip-cidr: "<load balancer addresses>"
# compute-full-forwarded-for stays at its default, "false"
```

The controller then trusts the header only from those addresses, discards any
entries a client added further left, and sends the result as the only
`X-Forwarded-For` entry. Leave `waldur.trustedProxyCount` empty (1): the
per-address limit, access subnets, token network restrictions, resource network
rules, the event log and `ingress.whitelistSourceRange`/`whitelistSourceRangeAdmin`
all see the same address.

Never enable `use-forwarded-headers` with the default
`proxy-real-ip-cidr: 0.0.0.0/0`: the controller then trusts the header from
anyone, so any client can forge its address and get past `whitelistSourceRange`
and `whitelistSourceRangeAdmin`.

### Alternative: keep the full header and count two proxies

With `compute-full-forwarded-for: "true"` as well, the controller passes the
balancer's header on and appends the address it received the request from.
Then set:

```yaml
waldur:
  trustedProxyCount: 2
```

Traefik works this way when the entry point's `forwardedHeaders.trustedIPs`
lists the balancer's addresses, so it needs this setup and its caveats.

The per-address limit then counts the entry the balancer added, but:

- The first entry is still whatever the client sent, so access subnets, token
  network restrictions, resource network rules and the event log can be
  forged. Do not use this setup if you rely on them, unless the load balancer
  replaces `X-Forwarded-For` rather than appending to it.

- The ingress must be reachable only through the load balancer. Reached
  directly, a count of 2 lets a client choose the address the limit counts, and
  so evade it by changing the address on every attempt.

Never set `trustedProxyCount` higher than the number of proxies that add an
entry: entries further left come from the client. `0` ignores the header.

### Checking the result

Sign in once with a wrong password from a machine whose public address you
know, then open Django admin, **Axes**, **Access attempts**. The attempt must
show that address, not the load balancer's or an ingress pod's: Axes records
the address resolved with `trustedProxyCount`, the one the per-address limit
counts.
