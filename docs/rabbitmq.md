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
  helm install rmq bitnami/rabbitmq --version 10.3.5 -f rmq-values.yaml
```

## Configuration

You can change rabbitmq config with the following variables in `rmq-values.yaml`:

1. `replicaCount` - number RMQ instances
2. `persistence.enabled` - enable/disable persistence
3. `persistence.size` - size for singe PV
4. `persistence.storageClass` - storage class for PV
5. `auth.username` - username for RMQ user
6. `auth.password` - password for RMQ user

For more config values, see [this section](https://github.com/bitnami/charts/tree/master/bitnami/rabbitmq#parameters)

In `values.yaml` file, you need to setup the following vars (`rabbitmq` prefix):

1. `user` - should be same as `auth.username` in the `rmq-values.yaml` file
2. `password` - should be same as `auth.password` in the `rmq-values.yaml` file
3. `host` - rabbitmq-ha service **hostname**
    (See [this doc](service-endpoint.md) for details)
4. `customManagementPort` - custom port for rabbitmq management interface
5. `customAMQPPort` - custom port for AMQP access
