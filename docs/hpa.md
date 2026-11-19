# HPA setup and configuration

It is possible to use cpu-utilization-based HPA
for API server (aka waldur-mastermind-api) and
Celery executor (aka `waldur-mastermind-worker` and `waldur-mastermind-beat`) pods.

The chart renders `autoscaling/v2` HorizontalPodAutoscalers, served by
Kubernetes 1.23 and later. The `autoscaling/v2beta2` API the chart used before
was removed in Kubernetes 1.26.

While an HPA is enabled, `replicaCount.api` / `replicaCount.worker` no longer
set the Deployment's `replicas`, so a `helm upgrade` does not reset the count
the HPA chose. The chart looks the running Deployment up instead and renders
its current count, which leaves it as it is. Leaving the field out would not
do: once an earlier release set it, Helm would delete it and Kubernetes would
fall back to 1.

The lookup finds nothing on a first install, where the Deployment starts at 1
until the HPA scales it, and wherever the chart is rendered without access to
the cluster: `helm template`, a client-side `--dry-run`, and GitOps tools such
as Argo CD. Rendered that way, `replicas` is left out, and the upgrade that
turns an HPA on can drop a running Deployment to 1 until the HPA next scales
it. With a GitOps tool, have it leave `spec.replicas` of these Deployments
alone (in Argo CD, `ignoreDifferences` with the `RespectIgnoreDifferences`
sync option).

`replicaCount: 0` is still rendered: an HPA does not scale up from 0, so a
passive standby site stays down. A Deployment found at 0 is not kept there,
so raising `replicaCount` again hands it back to the HPA.

## Setup

If you use minikube, you need to enable `metrics-server` using next command:
`minikube addons enable metrics-server`

## Configuration

In `values.yaml` file you can configure HPA for:

1. API server (`hpa.api` prefix):

    1.1 `enabled` - flag for enabling HPA.
        Possible values: `true` for enabling and `false` for disabling.

    1.2 `resources` - custom resources for server.
        `requests.cpu` param is mandatory for proper HPA work.

    1.3 `cpuUtilizationBorder` - border percentage of
        average CPU utilization per pod for deployment.

    1.4 `minReplicas` - lowest number of API pods the HPA scales down to.
        Defaults to `1`; must be at least `1`.

    1.5 `maxReplicas` - highest number of API pods the HPA scales up to.
        Defaults to `10`; must not be lower than `minReplicas`.

2. Celery (`hpa.celery` prefix):

    2.1 `enabled` - flag for enabling HPA, the same possible values as for API server.

    2.2 `workerResources` - custom resources for celery worker.
        `requests.cpu` param is mandatory for proper HPA work.

    2.3 `beatResources` - custom resources for celery beat.
        `requests.cpu` param is mandatory for proper HPA work.

    2.4 `cpuUtilizationBorder` - border percentage of
        average CPU utilization per pod for deployment.

    2.5 `minReplicas` - lowest number of worker pods the HPA scales down to.
        Defaults to `1`; must be at least `1`.

    2.6 `maxReplicas` - highest number of worker pods the HPA scales up to.
        Defaults to `10`; must not be lower than `minReplicas`.
        Only the worker is scaled: beat is a singleton.

Example:

```yaml
hpa:
  api:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    cpuUtilizationBorder: 70
  celery:
    enabled: true
    minReplicas: 1
    maxReplicas: 8
    cpuUtilizationBorder: 80
```
