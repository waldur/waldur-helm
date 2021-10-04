# RabbitMQ configuration

For rabbitmq installation,
[bitnami/rabbitmq](https://github.com/bitnami/charts/tree/master/bitnami/rabbitmq)
is used.

## Installation

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install rabbitmq-ha release:

```bash
  helm install rmq bitnami/rabbitmq -f rmq-values.yaml
```

## Configuration

You can change rabbitmq config with the following variables in `rmq-values.yaml`:

1. `replicaCount` - number RMQ instances
1. `persistence.enabled` - enable/disable persistence
1. `persistence.size` - size for singe PV
1. `persistence.storageClass` - storage class for PV
1. `auth.username` - username for RMQ user
1. `auth.password` - password for RMQ user

For more config values, see [this section](https://github.com/bitnami/charts/tree/master/bitnami/rabbitmq#parameters)

In `values.yaml` file, you need to setup the following vars (`rabbitmq` prefix):

1. `user` - should be same as `auth.username` in the `rmq-values.yaml` file
1. `password` - should be same as `auth.password` in the `rmq-values.yaml` file
1. `host` - rabbitmq-ha service **hostname**
    (See [this doc](service-endpoint.md) for details)
1. `customManagementPort` - custom port for rabbitmq management interface
1. `customAMQPPort` - custom port for AMQP access
