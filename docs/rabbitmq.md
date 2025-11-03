# RabbitMQ Configuration

## Production vs Demo Deployments

⚠️ **Important:** This document describes RabbitMQ setup for **demo/development environments only**.

**For production deployments**, use the [RabbitMQ Cluster Operator](rabbitmq-operator.md) instead of the Bitnami Helm chart. The operator provides:
- Better lifecycle management and high availability
- Production-grade monitoring and backup capabilities
- Automatic scaling and rolling upgrades
- Enhanced security and networking features

## Demo/Development Installation

For development and demo environments,
[bitnami/rabbitmq](https://github.com/bitnami/charts/tree/master/bitnami/rabbitmq)
can be used for quick setup.

## Demo Installation

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install RabbitMQ release for demo/development:

```bash
  helm install rmq bitnami/rabbitmq --version 15.0.2 -f rmq-values.yaml
```

**Note:** 
- The default configuration in `rmq-values.yaml` uses `bitnamilegacy` Docker images for compatibility
- This setup is **not recommended for production use**

## Demo Configuration

You can change rabbitmq config with the following variables in `rmq-values.yaml`:

1. `replicaCount` - number RMQ instances
2. `persistence.enabled` - enable/disable persistence
3. `persistence.size` - size for singe PV
4. `persistence.storageClass` - storage class for PV
5. `auth.username` - username for RMQ user
6. `auth.password` - password for RMQ user

For more config values, see [this section](https://github.com/bitnami/charts/tree/master/bitnami/rabbitmq#parameters)

**Important:** 
- The RabbitMQ configuration uses legacy Bitnami images (`bitnamilegacy/rabbitmq`) for demo/development compatibility
- This image is configured in the `rmq-values.yaml` file
- For production deployments, migrate to the [RabbitMQ Cluster Operator](rabbitmq-operator.md)

In `values.yaml` file, you need to setup the following vars (`rabbitmq` prefix):

1. `auth.username` - should be same as `auth.username` in the `rmq-values.yaml` file
2. `auth.password` - should be same as `auth.password` in the `rmq-values.yaml` file
3. `host` - rabbitmq service **hostname**
    (See [this doc](service-endpoint.md) for details)
4. `customManagementPort` - custom port for rabbitmq management interface
5. `customAMQPPort` - custom port for AMQP access

## Additional Protocol Support

The chart supports additional messaging protocols beyond AMQP:

- **MQTT** (port 1883) - for IoT device communication
- **STOMP** (port 61613) - for simple text-based messaging
- **WebSocket variants** (ports 15674, 15675) - for browser-based connections

These protocols are enabled through the `extraPlugins` configuration:

```yaml
extraPlugins: "rabbitmq_auth_backend_ldap rabbitmq_mqtt rabbitmq_web_mqtt rabbitmq_management rabbitmq_web_stomp rabbitmq_stomp"
```

Additional container and service ports are automatically configured for these protocols.
