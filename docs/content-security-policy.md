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
or mastermind: a 403 from the source range allow-list, a 413 from the request
body limit, a 429 from rate limiting, and a 502, 503 or 504 when the backend
is down or slow. Where the controller can do so, the chart sends mastermind's
API policy on those pages, on the homeport, API and API admin ingresses alike:

```text
Content-Security-Policy: default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
```

| `ingress.className` / path | Pages |
| --- | --- |
| `nginx` | 403, 413, 429, 502, 503 and 504 (`more_set_headers -s` in the `configuration-snippet` annotation). A backend response with one of these statuses gets this policy in place of its own, because the snippet cannot tell them apart. |
| `haproxy` | 403, 413, 429, 502, 503 and 504, including "no server available" (`http-after-response` in the `backend-config-snippet` annotation). A backend response that carries a policy of its own keeps it. |
| `openshift-default` | None: the OpenShift router ignores the `haproxy.org` annotations |
| `traefik` | None: the headers middleware cannot set a header on error responses only |
| Gateway API | None: Gateway API has no filter for the gateway's own error responses |

The nginx snippets, these and the chart's others, need snippet annotations
allowed on the ingress-nginx controller. Set `allow-snippet-annotations: "true"`
in its ConfigMap and, from ingress-nginx 1.12 on, also
`annotations-risk-level: Critical`, since snippets are rated Critical. Without
them the controller rejects or ignores the Ingress.
