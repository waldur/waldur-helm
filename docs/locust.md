# Locust cofiguration

This chart uses Locust tool for stress testing.

## Installation

Locust runs as another standalone Helm release.

Install Locust:

```bash
  helm install locust stable/locust -f locust-values.yaml
```

After release installation, some instructions regarding access to WEB UI
for Locust printed in stdout.See [this section](https://docs.locust.io/en/stable/quickstart.html#locust-s-web-interface)
for more information about UI interaction.

## Configuration

You can change locust config with the folloving variables in `locust-values.yaml`:

1. `image.repository` - repository of locust image
1. `image.tag` - tag of locust image
1. `master.config` - key-value configuration records
    for locust master (used as container env vars)
1. `master.config.locust-host` - URL of target mastermind service.
    See [this doc](service-endpoint.md) for details
1. `master.config.target-host` - same as `master.config.locust-host`
1. `master.config.locust-mode-master` - master mode flag. Please, don't change it,
    because for new versions of locust this flag is mandatory for a master node.
1. `master.config.locust-locustfile` - path to the injected locust file.
    Please, don't change file directory (`/locust-tasks/`),
    because it is fixed mountpoint for pods.
    The filename itself can have any value,
     but should be the same as key in the configmap (`worker.config.configmapName`).
1. `worker.config` - key-value configuration records
    for locust worker (used as container env vars).
1. `worker.config.configmapName` - name of configmap with locustfile
1. `worker.config.locust-mode-worker` - worker mode flag.
    Please, don't change it, because for new versions of locust
    this flag is mandatory for a worker node.
1. `worker.config.locust-locustfile` - path to the injected locust file.
    Same rules as for `master.config.locust-locustfile`.
1. `worker.config.locust-master-node-host` - hostname of the locust master service,
    which is formatted as `<locust_release_name>-master-svc`
1. `worker.replicaCount` - number of locust workers

You can find available variables for master and worker configuration
[from chart desription](https://github.com/helm/charts/tree/master/stable/locust#installing-the-chart)
and
[official locust documentation](https://docs.locust.io/en/stable/configuration.html#all-available-configuration-options)
(most of the flags and args can be injected through env vars).

**NB**: The original helm chart image (`greenbirdit/locust:0.9.0`)
has outdated locust version and doesn't support most of
the current env variables from the first link above.
Thus `master.config.target-host` is used only for compatibility
and must be equal to `master.config.locust-host`

In the `values.yaml` you need to setup the following vars (`stressTesting` prefix):

1. `enabled` - enable/disable stress testing
1. `locustFilePath` - path to the locust file (should be in the `waldur/` directory)
