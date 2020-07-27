## RabbitMQ configuration
For rabbitmq installation, [stable/rabbitmq-ha](https://github.com/helm/charts/tree/master/stable/rabbitmq-ha) is used.
### Installation
Install rabbitmq-ha release:
```
  helm install rmq stable/rabbitmq-ha -f rmq-values.yaml
```
### Configuration
You can change rabbitmq config with the following variables in `rmq-values.yaml`:
1. `replicaCount` - number RMQ instances
2. `persistentVolume.enabled` - enable/disable persistence
3. `persistentVolume.name` - name prefix for persistent volume per each RMQ instance
4. `persistentVolume.size` - size for singe PV
5. `persistentVolume.storageClass` - storage class for PV
6. `rabbitmqUsername` - username for RMQ user
7. `rabbitmqPassword` - password for RMQ user 
8. `prometheus.operator.enabled` - enable/disable prometeus operator connection

For more config values, see [this section](https://github.com/helm/charts/tree/master/stable/rabbitmq-ha#configuration)

In `values.yaml` file, you need to setup the following vars (`rabbitmq` prefix):
1. `user` - should be same as `rabbitmqUsername` in the `rmq-values.yaml` file
2. `password` - should be same as `rabbitmqPassword` in the `rmq-values.yaml` file
3. `hostPrefix` - should be same as rabbitmq-ha release name (see `Installation` section above)
4. `customManagementPort` - custom port for rabbitmq management interface 
5. `customAMQPPort` - custom port for AMQP access
