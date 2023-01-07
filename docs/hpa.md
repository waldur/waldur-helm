# HPA setup and configuration

It is possible to use cpu-utilization-based HPA
for API server (aka waldur-mastermind-api) and
Celery executor (aka `waldur-mastermind-worker` and `waldur-mastermind-beat`) pods.

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

2. Celery (`hpa.celery` prefix):

    2.1 `enabled` - flag for enabling HPA, the same possible values as for API server.

    2.2 `workerResources` - custom resources for celery worker.
        `requests.cpu` param is mandatory for proper HPA work.

    2.3 `beatResources` - custom resources for celery beat.
        `requests.cpu` param is mandatory for proper HPA work.

    2.4 `cpuUtilizationBorder` - border percentage of
        average CPU utilization per pod for deployment.
