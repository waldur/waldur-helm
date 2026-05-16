# Waldur Helm Chart — Development Guide

Helm chart that packages Waldur (mastermind API + worker + beat, homeport SPA, supporting services) for Kubernetes. The published chart at `https://waldur.github.io/waldur-helm/` is the upstream-supported way to install Waldur on a cluster.

## Repository layout

```text
waldur-helm/
├── waldur/                       # The chart itself
│   ├── Chart.yaml                # apiVersion: v2 — name "waldur", version + appVersion tracked together
│   ├── values.yaml               # Default values (image tags, replica counts, resource limits, SAML, SMTP, etc.)
│   ├── templates/                # 61 templates: deployments, services, ingresses, configmaps, cronjobs, HPAs, network policies, secrets
│   ├── tests/                    # helm-unittest specs (config-whitelabeling_test.yaml, deployment-homeport_test.yaml)
│   └── test/                     # Test values + fixtures (values.yaml, k8s/, images/, ssh/, mastermind_templates/)
├── docs/                         # Operator documentation (synced into waldur-docs)
├── scripts/
│   └── set-version.sh            # Bumps Chart.yaml + waldur.imageTag + waldur.homeport.imageTag
├── applicationset.yaml           # ArgoCD ApplicationSet definition for managed deployments
├── postgresql-values.yaml        # Reference values for the bundled Bitnami postgresql sub-chart
├── postgresql-ha-values.yaml     # Reference values for postgresql-ha sub-chart
├── rmq-values.yaml               # Reference values for the bundled Bitnami rabbitmq sub-chart
├── minio-values.yaml             # Reference values for optional MinIO (used by DB-backup cronjobs)
└── README.md                     # User-facing install instructions
```

## Chart structure

- Single chart `waldur` (no umbrella, no subcharts beyond Bitnami dependencies).
- Three optional Bitnami dependencies declared in `Chart.yaml`, gated by conditions in values:
  - `postgresql` (cond `postgresql.enabled`) — single-node Postgres for quick setup.
  - `postgresqlha` (cond `postgresqlha.enabled`) — Postgres HA for production.
  - `rabbitmq` (cond `rabbitmq.enabled`) — task queue for Celery workers.
- Use one of `postgresql.enabled` / `postgresqlha.enabled` / external DB (`docs/external-db-integration.md`) — never two of them.
- Mastermind image: `waldur.imageName` / `waldur.imageTag` (defaults to `opennode/waldur-mastermind`).
- Homeport image: `waldur.homeport.imageName` / `waldur.homeport.imageTag`.

## Key template families

- **Deployments**: `deployment-api.yaml`, `deployment-worker.yaml`, `deployment-beat.yaml`, `deployment-homeport.yaml`, `deployment-metrics-exporter.yaml`, `deployment-uvk-everypay.yaml`, `deployment-waldur-db-restore.yaml`.
- **Cronjobs**: `cronjob-waldur-cleanup.yaml`, `cronjob-waldur-db-backup.yaml` + `-rotation`, `cronjob-waldur-saml2-metadata-sync.yaml`.
- **Configmaps** (`config-*.yaml`): every server-side config file is rendered into a configmap and mounted into the pod. Adding a new config file means adding both the configmap template and the volume mount in the relevant deployment.
- **Init jobs**: `job-init-whitelabeling.yaml` runs once per release; must be deleted before `helm upgrade` (see README "Waldur Helm chart release upgrading"). The same applies to `load-features-job` when present.
- **Ingresses**: separate ingresses per surface (`ingress-api.yaml`, `ingress-api-admin.yaml`, `ingress-homeport.yaml`, `ingress-rmq-ws.yaml`, `ingress-uvk-everypay.yaml`). Cert-manager `letsencrypt-issuer.yaml` and `certificate-*.yaml` for TLS.
- **Network policies** are opt-in; gate by values when adding new ones.
- **HPAs**: `hpa-api.yaml`, `hpa-worker.yaml` — only rendered when corresponding `*Hpa.enabled` is true.
- **Traefik middlewares** (`traefik-middleware-*.yaml`): rendered only when the cluster uses Traefik as its ingress controller.

## Local development workflow

```bash
# Pull Bitnami dependencies
helm dependency update waldur/

# Lint
helm lint waldur/
helm lint waldur/ -f waldur/test/values.yaml

# Render templates without installing
helm template waldur waldur/ -f waldur/test/values.yaml --output-dir /tmp/rendered --debug

# Unit tests (helm-unittest plugin required)
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v0.8.2
helm unittest waldur/

# Dry-run install
helm install waldur waldur/ -f waldur/test/values.yaml --dry-run --debug

# Full install on a test cluster (minikube/etc.)
helm install waldur waldur/ -f waldur/test/values.yaml --wait --timeout 20m0s
```

`waldur/test/values.yaml` is the canonical fixture for CI tests — keep it install-able so `Test release installation and readiness` passes.

## Version bumping

```bash
./scripts/set-version.sh 8.0.10
```

Updates atomically:

- `waldur/Chart.yaml` → `version` and `appVersion`
- `waldur/values.yaml` → `waldur.imageTag` (mastermind)
- `waldur/values.yaml` → `waldur.homeport.imageTag`

Always use the script (BSD/GNU-portable sed) rather than hand-editing.

## CI behaviour

CI pulls templates from `waldur/waldur-pipelines`. Jobs:

| Job | When | What |
|---|---|---|
| `Run linter` | MRs, master, tags | `helm dep update` + `helm lint` (twice: default & test values) + `helm unittest`, then renders templates and `py_compile`s the rendered override config |
| `Validate release installation (dry-run)` | MRs, master, tags | `helm install --dry-run --debug` against the test k8s cluster |
| `Test release installation and readiness` | MRs / scheduled / triggered, when `waldur/**` changed | Real `helm install --wait --timeout 20m0s` on the test cluster, then `helm list` |
| `Test ArgoCD sync` | similar | Validates `applicationset.yaml` syncs cleanly |
| `Cleanup previous test deployment` | pre-stage | `helm uninstall` + delete leftover jobs/PVCs to keep the test cluster healthy |
| `Publish new chart version and update docs on github` | on tag | Packages the chart, pushes to the `gh-pages` branch (the `waldur.github.io/waldur-helm/` index) |
| `Check for deprecated Kubernetes resources` | periodic | Catches drift against current k8s APIs |

CI cluster credentials are in `K8S_CONFIG_WALDUR_HELM_TEST` (GitLab CI variable).

## Conventions / gotchas

- **Configmap + volume mount**: new server-side config files require (a) `config-*.yaml` template, (b) volume + volumeMount in every relevant deployment, (c) corresponding entry in `values.yaml`.
- **Bitnami dep upgrades**: bump version in `Chart.yaml` only after testing locally — Bitnami's chart-level breaking changes are routine. Run `helm dep update waldur/` and inspect `Chart.lock`.
- **`init-whitelabeling-job` and `load-features-job`** must be deleted before `helm upgrade` (the README spells this out). Anyone scripting upgrades around this chart should bake this in.
- **One DB chart at a time**: enabling both `postgresql.enabled` and `postgresqlha.enabled` will collide. See `docs/migration-from-psql-ha.md` for moving between them.
- **`docs/` content is synced** into the `waldur-docs` repo via `external-sources.yml` there. Edit here; don't edit the synced copy in waldur-docs.
- **Test values matter**: `waldur/test/values.yaml` is what CI installs. New required values must land there too or the install job fails.
- **Skip flags**: most CI jobs honour `SKIP_TESTS=true|yes` to bail out — useful for docs-only changes.

## When to invoke this chart from the workspace

`waldur-mastermind`, `waldur-homeport`, and `js-client` are the source repos that produce the Docker images this chart consumes. When a backend or frontend MR adds a new mandatory configuration option, this chart needs a matching update:

1. Add the option to `waldur/values.yaml` with a safe default.
2. Render it into the appropriate `config-*.yaml` configmap (or env var on the deployment).
3. Add a unit test in `waldur/tests/` if the value affects rendered output.
4. Document it in `docs/components.md` (or the relevant section under `docs/`).

For Docker-only deployments (no Kubernetes), the analogous changes live in `waldur-docker-compose`.
