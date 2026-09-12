# Gateway API support

Alongside the [Ingress](tls-config.md)/[IP whitelisting](ip-whitelisting.md) resources the chart
has always rendered, it can also render [Gateway API](https://gateway-api.sigs.k8s.io/) `HTTPRoute`
resources for the same services (mastermind API, admin, homeport, RabbitMQ STOMP over WebSocket,
UVK Everypay, Matrix chat). Both mechanisms can be enabled at once -- `ingress.enabled` and
`gatewayAPI.enabled` are independent switches -- which is useful while migrating a cluster from an
Ingress controller to a Gateway API implementation.

The Gateway API CRDs (`gateway.networking.k8s.io/v1`) and a controller that implements them (Envoy
Gateway, NGINX Gateway Fabric, Istio, Traefik, ...) must already be installed on the cluster; the
chart never installs them. If `gatewayAPI.enabled` is true but the CRDs aren't present, every
`HTTPRoute`/`Gateway` template fails at render time with a clear message rather than being silently
skipped or failing later at `kubectl apply` with an opaque "no matches for kind" error.

## Enabling it

Minimal setup, attaching to a Gateway that already exists in the cluster:

```yaml
gatewayAPI:
  enabled: true
  parentRefs:
    - name: my-gateway
      namespace: gateway-infra # only needed if the Gateway lives in a different namespace
```

Or have the chart create and manage its own Gateway:

```yaml
gatewayAPI:
  enabled: true
  createGateway: true
  gatewayClassName: "envoy-gateway" # your cluster's GatewayClass
```

With no `gatewayAPI.listeners` supplied, `createGateway: true` renders a single plain HTTP listener
named `http` on port 80 -- enough to route unencrypted traffic and to prove the wiring end to end.
For a real deployment you'll want HTTPS with TLS termination; see below.

## TLS

TLS in Gateway API is a **Gateway-level** concern, not a per-route one (unlike the ingress path,
where each of the `ingress-*.yaml` templates carries its own `tls:` block). Supply your own HTTPS
listener(s) via `gatewayAPI.listeners`, each templated with `tpl` so it can reference `.Values`:

```yaml
gatewayAPI:
  enabled: true
  createGateway: true
  gatewayClassName: "envoy-gateway"
  tls:
    enabled: true
    source: "letsEncrypt"
    clusterIssuerName: "letsencrypt-prod-issuer"
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
    - name: https-api
      protocol: HTTPS
      port: 443
      hostname: "{{ .Values.apiHostname }}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: api-certificate # cert-manager creates this Secret for you below
      allowedRoutes:
        namespaces:
          from: Same
    - name: https-homeport
      protocol: HTTPS
      port: 443
      hostname: "{{ .Values.homeportHostname }}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: homeport-certificate
      allowedRoutes:
        namespaces:
          from: Same
```

Setting `gatewayAPI.tls.source: "letsEncrypt"` puts the same `cert-manager.io/cluster-issuer`
annotation on the Gateway that the ingress templates put on each `Ingress` object -- cert-manager
1.14+ watches `Gateway` resources and provisions a `Certificate` per listener that has
`certificateRefs` set, exactly as it would per-Ingress. Point each listener's `certificateRefs` at
whatever Secret name you want cert-manager (or your own PKI) to produce.

### HTTP -> HTTPS redirect

When `gatewayAPI.createGateway: true` and `gatewayAPI.tls.enabled: true`, the chart renders one
shared `HTTPRoute` (`templates/httproute-redirect.yaml`) that redirects all traffic on the `http`
listener to HTTPS. This is deliberately **one route for every hostname/path**, unlike Ingress where
each of the 6 `ingress-*.yaml` templates carried its own `force-ssl-redirect` annotation: a Gateway
API `RequestRedirect` filter can't be combined with a rule that also serves real backend traffic
(the redirect always wins), so it has to live on a route that only matches the plain-HTTP listener
-- hence one route, attached via `sectionName: http`.

This route assumes the chart's own default HTTP listener, named `http`. If you override
`gatewayAPI.listeners`, keep one listener named `http` for the automatic redirect to keep working,
or drop it and handle the redirect yourself.

With `gatewayAPI.createGateway: false` (attaching to an existing Gateway), the chart doesn't own
that Gateway's listener names, so it doesn't render a redirect route at all -- either add your own
`HTTPRoute` targeting that Gateway's HTTP listener, or configure the redirect on the Gateway
implementation itself.

## Feature support matrix

Gateway API's core spec covers most of what the chart's Ingress annotations do today, but not all
of it -- some features remain implementation-specific, with no standard resource:

| Feature | Ingress today | Gateway API | Portable? |
| --- | --- | --- | --- |
| SSL redirect | `force-ssl-redirect` annotation | `RequestRedirect` filter | Yes -- native |
| Path rewrite | `rewrite-target` annotation | `URLRewrite` filter (`ReplacePrefixMatch`) | Yes -- native |
| CSP / response headers | `configuration-snippet` | `ResponseHeaderModifier` filter | Yes -- native |
| TLS termination | per-Ingress `tls:` block | Gateway listener `tls.mode: Terminate` | Yes -- native |
| cert-manager | `cert-manager.io/cluster-issuer` | same annotation, on the Gateway | Yes -- native |
| CORS | `enable-cors` + `cors-*` annotations | none | No -- `extraPolicies` |
| IP allow-listing | `whitelist-source-range` | none | No -- `extraPolicies` |
| Proxy body/buffer size | `proxy-body-size`, `proxy-buffer-size` | none | No -- `extraPolicies` |

The chart renders the portable ones natively (see `templates/httproute-*.yaml`). For the rest, use
the escape hatch below.

## `extraPolicies`: implementation-specific policies

`gatewayAPI.extraPolicies` is a list of raw manifests, rendered as-is and passed through `tpl` --
so entries may reference `.Values`, including the ingress values already defined above, to keep one
source of truth across both paths:

```yaml
gatewayAPI:
  extraPolicies:
    - |
      apiVersion: gateway.envoyproxy.io/v1alpha1
      kind: SecurityPolicy
      metadata:
        name: waldur-cors
      spec:
        targetRefs:
          - group: gateway.networking.k8s.io
            kind: HTTPRoute
            name: api-httproute
        cors:
          allowOrigins:
            - "https://*"
          allowMethods: [GET, POST, PUT, PATCH, DELETE, OPTIONS]
          allowHeaders:
            - DNT
            - Keep-Alive
            - User-Agent
            - X-Requested-With
            - If-Modified-Since
            - Cache-Control
            - Content-Type
            - Range
            - Authorization
            - sentry-trace
            - baggage
            - X-Impersonated-User-Uuid
          exposeHeaders:
            - Link
            - X-Result-Count
    - |
      apiVersion: gateway.envoyproxy.io/v1alpha1
      kind: SecurityPolicy
      metadata:
        name: waldur-ip-allowlist
      spec:
        targetRefs:
          - group: gateway.networking.k8s.io
            kind: HTTPRoute
            name: api-httproute
        authorization:
          defaultAction: Deny
          rules:
            - name: allow-internal
              action: Allow
              principal:
                clientCIDRs:
                  - "{{ .Values.ingress.whitelistSourceRange }}"
```

HTTPRoute names to target with `targetRefs` (each is `metadata.name` of the corresponding
`templates/httproute-*.yaml`): `api-httproute`, `api-admin-httproute`, `homeport-httproute`,
`rabbitmq-ws-httproute`, `uvk-everypay-httproute`, `matrix-httproute`. The admin-specific IP
allow-list (the ingress path's separate `whitelistSourceRangeAdmin`) is just another
`SecurityPolicy` targeting `api-admin-httproute`.

### Recommended implementations

**Envoy Gateway** is the recommended implementation for this chart: CORS, IP allow-listing and
proxy tuning all have first-class typed CRDs (`SecurityPolicy`, `ClientTrafficPolicy`,
`BackendTrafficPolicy`), matching the examples above.

**NGINX Gateway Fabric** covers the same features via `SnippetsFilter` (raw nginx directives,
must be enabled with the `--snippets-filters` controller flag) and `ClientSettingsPolicy` /
`ProxySettingsPolicy` for body/buffer size -- see the [NGINX Gateway Fabric
docs](https://docs.nginx.com/nginx-gateway-fabric/) for the exact CRD shape.

Other implementations (Istio `AuthorizationPolicy`/`VirtualService`, Traefik `Middleware`) work the
same way: write the implementation's policy CRD as an `extraPolicies` entry, targeting the
`HTTPRoute` by name.

## Migrating from Ingress

Gateway API support is additive, not a replacement -- there's no forced cutover:

1. Install the Gateway API CRDs and a controller (e.g. Envoy Gateway) on the cluster.
2. Set `gatewayAPI.enabled: true` alongside the existing `ingress.enabled: true` -- both render, so
   the Ingress controller keeps serving production traffic unchanged.
3. Point a test hostname (or your own client) at the new Gateway's address and verify each service
   through it.
4. Move any CORS/IP-allowlist/proxy-tuning configuration from the `ingress.*` annotations into
   `gatewayAPI.extraPolicies` (see the matrix above for what's native vs. not).
5. Cut DNS over to the Gateway's address, then set `ingress.enabled: false` once traffic has moved.
