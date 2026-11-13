# Content-Security-Policy

The homeport image sends the portal's Content-Security-Policy (CSP) on every
response it serves: `index.html`, assets, its own error pages and micro-apps.
It builds the policy at start from its environment, so the policy holds behind
any proxy. The chart sets the environment of the `waldur-homeport` container
and no longer adds a policy of its own at the ingress, the HTTPRoute or the
Traefik middleware.

This needs a homeport image that renders the policy from its environment.
Older images send only `frame-ancestors 'none'; object-src 'none';
base-uri 'self'`, so upgrade the chart and the image together.

To see what a deployment sends:

```bash
curl -sI https://<homeportHostname>/ | grep -i content-security-policy
```

## The policy

With nothing configured but `API_URL=https://api.example.org/`, the image sends
a strict allowlist:

```text
default-src 'self';
script-src 'self' 'wasm-unsafe-eval';
style-src 'self' 'unsafe-inline';
img-src 'self' https://api.example.org *.tile.openstreetmap.org blob: data:;
connect-src 'self' https://api.example.org wss://api.example.org nominatim.openstreetmap.org;
font-src 'self' data:;
media-src 'self' blob:;
worker-src 'self' blob:;
frame-src 'none';
form-action 'self';
object-src 'none';
base-uri 'none';
frame-ancestors 'none'
```

`script-src` allows no inline script and no `eval()`; `'wasm-unsafe-eval'`
allows compiling WebAssembly only, which the encryption in Matrix chat needs.
The image is the reference for the exact policy of its version.

## What the chart passes

The chart derives these from values it already has:

| Variable | From | Added to |
| --- | --- | --- |
| `API_URL` | `apiScheme`, `apiHostname` | `connect-src`, `img-src`; its `ws://`/`wss://` origin to `connect-src` |
| `CSP_SENTRY_URL` | `waldur.homeport.customSentryURL`, else the origin of `waldur.sentryDSN` | `connect-src` |
| `CSP_MATOMO_URL` | `waldur.homeport.matomoUrlBase` | `script-src`, `connect-src`, `img-src` |
| `CSP_MATRIX_URL` | `https://<matrixChat.homeserver.serverName>` (scheme from `apiScheme`) | `connect-src`, `img-src`, `media-src` |
| `CSP_MATRIX_CALL_URL` | `wss://<serverName>`, plus the origin of `matrixChat.livekit.publicUrl` when it differs | `connect-src` |
| `CSP_INFERENCE_URL` | `waldur.homeport.inferencePlaygroundURL` | `connect-src` |

The Sentry SDK is bundled with the portal, so Sentry needs `connect-src` only.
A value that is empty is not passed, and adds nothing.

These come from `waldur.homeport.csp`:

| Value | Variable | Effect |
| --- | --- | --- |
| `formAction` | `CSP_FORM_ACTION` | Adds sources to `form-action` |
| `reportOnly` | `CSP_REPORT_ONLY` | `true` sends the policy as `Content-Security-Policy-Report-Only`, beside a minimal enforced one |
| `reportUri` | `CSP_REPORT_URI` | Endpoint browsers send violation reports to (`report-uri`) |
| `reportTo` | `CSP_REPORT_TO` | `true` also sends `report-to` and a `Reporting-Endpoints` header for `reportUri` |
| `extra` | `CSP_<DIRECTIVE>_EXTRA` | Adds sources to one directive |
| `policy` | `CSP_POLICY` | Replaces the whole policy |

`formAction` and each `extra` entry take a string of space-separated sources or
a list. `reportOnly` and `reportTo` take `true` or `false`; the chart refuses to
render with anything else, so a quoted `"false"` stays false.

The chart also refuses to render a value the homeport image would refuse at
start, since the new pod would otherwise crash-loop and the rollout hang. A
source may not contain `,` `;` `"` `\` `$` or a control character: separate
sources with spaces, or give a list, not a comma-separated string. `reportUri`
may not contain whitespace or `'` either. For `policy`, see below.

## SAML identity providers

With the HTTP-POST binding the portal submits a form straight to the identity
provider, so the provider's origin must be in `form-action`:

```yaml
waldur:
  homeport:
    csp:
      formAction:
        - https://idp.example.org
        - https://login.example.edu
```

A federation with many identity providers may set `formAction: "https:"`. That
still blocks `javascript:` and plain-HTTP targets.

## Rolling out in report-only mode

A policy that blocks something the portal needs breaks that part of the portal,
so roll a new policy out without enforcing it first:

1. Deploy with report-only on and a reporting endpoint. A Sentry project's
   security endpoint works:

    ```yaml
    waldur:
      homeport:
        csp:
          reportOnly: true
          reportUri: "https://sentry.example.com/api/<project>/security/?sentry_key=<key>"
    ```

    Report-only mode does not leave the portal unprotected: beside the
    report-only policy, the image keeps
    `Content-Security-Policy: object-src 'none'; base-uri 'none'; frame-ancestors 'none'`
    enforced.

2. Prove that reports arrive before trusting their absence. Open the portal,
   and in the browser console run `fetch("https://csp-check.invalid/")`. The
   fetch fails, but the policy reports a `connect-src` violation for
   `csp-check.invalid`. Check that it reaches the endpoint; in Sentry it shows
   up among the project's security reports. If it does not arrive, reports are
   not being delivered and an empty report stream proves nothing: fix the
   delivery, or watch the browser console instead.
3. Use the portal as people do: sign-in with every method you offer, maps,
   Matrix chat and calls, the Monaco editor, analytics consent. Watch the
   reports and the browser console for `Content-Security-Policy-Report-Only`
   violations.
4. Add each missing source with `extra` or the values above, and deploy again.
5. When nothing but your own test violation is reported, set
   `reportOnly: false` to enforce. Keep `reportUri` to hear about violations
   later.

Reports go through `report-uri` by default. `reportTo: true` also sends a
`report-to` directive and a `Reporting-Endpoints` header. Chromium then reports
only through the Reporting API and ignores `report-uri`, and those reports need
a CORS preflight that a collector, Sentry's security endpoint among them, may
not accept. Turn `reportTo` on only after confirming that Reporting API reports
arrive, for example against Sentry on staging, with the check in step 2. It
needs `reportUri`; without one the image ignores it.

## Adding a source

`extra` appends sources to one directive. Its keys are directive names:
`default-src`, `script-src`, `style-src`, `img-src`, `connect-src`, `font-src`,
`media-src`, `worker-src`, `frame-src` and `form-action`. Each becomes
`CSP_<DIRECTIVE>_EXTRA` on the container; the chart refuses to render with any
other key. `frame-src` is the exception to appending: it is `'none'` by
default, and a `frame-src` entry replaces `'none'` rather than joining it.

```yaml
waldur:
  homeport:
    csp:
      extra:
        connect-src: "https://metrics.example.com"
        img-src:
          - https://cdn.example.com
          - https://tiles.example.com
```

## Replacing the policy

For a policy the values cannot express, `policy` replaces the whole of it
verbatim. `reportOnly`, `reportUri` and `reportTo` still apply. The chart
refuses to render it, as the image would refuse it at start, when it:

- does not state `object-src`, `base-uri` and `frame-ancestors`;
- runs two directives together because a line ended without `;` (a newline
  does not end a directive);
- contains `,` `"` `\` `$` or a control character;
- states `report-uri` while `reportUri` is set, or `report-to` while `reportTo`
  is on: give the endpoint in one place.

A replaced policy no longer follows the portal's needs as the image changes,
so check it after each upgrade.

```yaml
waldur:
  homeport:
    csp:
      policy: "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"
```

A policy added at a proxy in front of the portal can only tighten it, because
browsers enforce every policy a response carries. Change the portal's policy
here, not at the proxy.

## The proxies' own error pages

Some pages come from the ingress controller itself and never reach homeport
or mastermind: a 400 or 431 for a request it will not parse, a 403 from the
source range allow-list, a 413 from the request body limit, a 429 from rate
limiting, and a 502, 503 or 504 when the backend is down or slow. Where the
controller can do so, the chart sends mastermind's API policy on those pages,
on every Ingress it renders:

```text
Content-Security-Policy: default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
```

The same statuses cover a backend's own error page without a policy, such as
the one a server behind the Ingress writes for a request it cannot parse. The
mastermind image sets the policy on the error pages gunicorn writes itself, so
those carry it behind any proxy, Traefik and Gateway API included. The web
shell's own 400 for a malformed request (a bad request line, a CR in a header,
an HTTP/1.1 request without Host, a request line or a header over 8190 bytes)
is written by aiohttp before any web shell code runs, as `text/plain`, which
browsers do not render as a page; an HTTP/1.0 request without Host reaches the
web shell and gets its 403. Behind the chart's nginx Ingress, and HAProxy up to
3.2, that 400 gets the policy from the web shell Ingress's snippet; through
Traefik, Gateway API or directly it carries none.

| `ingress.className` / path | Pages |
| --- | --- |
| `nginx` | 400, 403, 413, 429, 431, 502, 503 and 504 (`more_set_headers -s` in the `configuration-snippet` annotation). A backend response with one of these statuses gets this policy in place of its own, because the snippet cannot tell them apart. It already does so for mastermind's 403 and 429. On the Ingresses in front of mastermind's API it leaves a 400 alone, because there the browsable API answers invalid input by rendering its form again in a 400 page, under mastermind's page policy; this one would stop its scripts and styles loading and the form being posted again. A request nginx rejects while parsing it never reaches these snippets; see [ingress-nginx](#ingress-nginx-controller-settings). |
| `haproxy` | On the HAProxy Kubernetes Ingress Controller up to 3.2: 400, 403, 413, 429, 431, 502, 503 and 504, on the pages HAProxy generates for a backend, such as a 503 when no server is available, and on backend responses without a policy (`http-after-response` in the `backend-config-snippet` annotation). A backend response that carries a policy of its own keeps it. The 403 and 429 from the allow-list and rate limiting come from HAProxy's frontend, which a backend snippet does not reach. From 3.4 the controller ignores snippet annotations, so the chart sets no policy on HAProxy's own pages there; see [HAProxy](#haproxy-controller-settings). |
| `openshift-default` | None: the OpenShift router ignores the `haproxy.org` annotations |
| `traefik` | None: the headers middleware cannot set a header on error responses only; see [Traefik and Gateway API](#traefik-and-gateway-api) |
| Gateway API | None: Gateway API has no filter for the gateway's own error responses |

The nginx snippets, these and the chart's others, need snippet annotations
allowed on the ingress-nginx controller. Set `allow-snippet-annotations: "true"`
in its ConfigMap and, from ingress-nginx 1.12 on, also
`annotations-risk-level: Critical`, since snippets are rated Critical. Without
them the controller rejects or ignores the Ingress.

A `nginx.ingress.kubernetes.io/configuration-snippet` given in
`ingress.annotations` replaces the chart's on every Ingress, error-page line
included, since an annotation holds one value and the later one is kept. If you
set one, include the chart's `more_set_headers` line from the rendered Ingress
in it.

### ingress-nginx controller settings

nginx answers some requests while it parses them, before it picks the
location an Ingress configures, so no Ingress's snippet applies to them: a
`NUL` byte in the path (`/%00`), a URI longer than its buffers (414) and a
header that does not fit them (494, sent as 400). Set the policy on those in
the controller's ConfigMap, at the `http` level:

```yaml
data:
  http-snippet: |
    map "$upstream_status:$status" $waldur_error_csp {
      "~^:[45]" "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
      default   "";
    }
    add_header Content-Security-Policy $waldur_error_csp always;
```

The policy goes only on a 4xx or 5xx response that nginx did not get from a
backend, where `$upstream_status` is empty; `add_header` adds nothing for an
empty value. A backend's response keeps its own policy, or its lack of one, and
nginx's own redirects, CORS answers and other `return` pages that are not
errors get none. That matters because the snippet applies to every Ingress the
controller serves. A 502 or 504 for an unreachable backend is not covered here,
since `$upstream_status` holds that status; the chart's per-Ingress snippets
cover it. An error page nginx serves from its cache has an empty
`$upstream_status` too, so it gets this policy beside its own, which only
tightens it.

When this snippet and an Ingress's `more_set_headers` both apply to an error
nginx generates in a location, such as an allow-list 403, the response carries
two policies and browsers enforce both; with the chart's snippets they are the
same policy.

With the ingress-nginx Helm chart, these keys go under `controller.config`. If
the ConfigMap already has an `http-snippet`, add these lines to it rather than
replacing it: the key holds one string, so pasting the block over it drops the
directives already there. Unlike snippet annotations, a ConfigMap snippet does
not depend on `allow-snippet-annotations` or `annotations-risk-level`: the
ConfigMap belongs to the cluster's operator.

### HAProxy controller settings

Config snippets work on the HAProxy Kubernetes Ingress Controller up to 3.2.
Version 3.4 dropped them: it ignores the snippet annotations and ConfigMap keys
and no longer has `--disable-config-snippets`, so on 3.4 neither the chart's
backend snippet nor the setting below sets a policy on HAProxy's own pages.
Upstream's replacement is validated custom annotations or the Backend and
Frontend custom resources.

Up to 3.2, the 403 and 429 that the controller generates for the allow-list and
rate limiting come from its frontend. Set the policy there with
`frontend-config-snippet`, a ConfigMap-only key that the controller inserts
into its main http and https frontends:

```yaml
data:
  frontend-config-snippet: |
    http-after-response set-header Content-Security-Policy "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" if { status 400 403 408 413 429 431 500 502 503 504 } !{ res.hdr(content-security-policy) -m found }
```

It applies to every Ingress that controller serves, which is why it sets the
policy only on error statuses and keeps one a backend sends. It also covers
the pages HAProxy generates for an unreachable or slow backend. If the
ConfigMap already has a `frontend-config-snippet`, add this line to it rather
than replacing it: the key holds one string, so pasting the block over it
drops the directives already there. A controller up to 3.2 started with
`--disable-config-snippets=frontend` (or `all`) ignores it.

HAProxy answers a request it cannot parse at all with a 400 before
`http-after-response` runs, so that page stays without a policy. A custom
`errorfile` for it had no effect in testing.

### Traefik and Gateway API

Traefik's headers middleware sets a header on every response or on none. Its
`errors` middleware can send chosen statuses to a small service that answers
with the policy: Traefik then returns that service's headers and body with the
original status. In testing that held for a backend's error page and for
Traefik's own 502 for an unreachable backend. Since it replaces the body, use
it for statuses whose body no client reads, such as 502 to 504; a 400 or 403
from the API carries the error a client shows. Traefik's own 404 for a path no
router matches passes no middleware.

What a Gateway API implementation sends on its own error pages depends on the
implementation, and the HTTPRoute API cannot change it.

### Checking a deployment

Ask for a page the controller generates itself, such as the one for a `NUL`
byte in the path:

```bash
curl -si 'https://<host>/%00' | grep -i content-security
```

On ingress-nginx this needs the `http-snippet` above; without it, the 400
comes back without a policy.
