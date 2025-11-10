# RabbitMQ Cluster Operator (Production)

For **production deployments**, it is strongly recommended to use the official [RabbitMQ Cluster Kubernetes Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview) instead of the Bitnami Helm chart. The operator provides better lifecycle management, high availability, and production-grade features.

## Overview

The RabbitMQ Cluster Operator automates:

- Provisioning and management of RabbitMQ clusters

- Scaling and automated rolling upgrades

- Monitoring integration with Prometheus and Grafana

- Backup and recovery operations

- Network policy and security configurations

## Prerequisites

- Kubernetes cluster version 1.19 or above

- Configured `kubectl` access

- Appropriate RBAC permissions

## Installation

### 1. Install the RabbitMQ Cluster Operator

```bash
kubectl apply -f "<https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml">
```

Verify the operator is running:

```bash
kubectl get pods -n rabbitmq-system
```

### 2. Create a Production RabbitMQ Cluster

Create a production-ready RabbitMQ cluster configuration:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: waldur-rabbitmq
  namespace: default
spec:
  # Production recommendation: use odd numbers (3, 5, 7)
  replicas: 3

  # Resource configuration
  resources:
    requests:
      cpu: 1000m      # 1 CPU core
      memory: 2Gi     # Keep requests and limits equal for stability
    limits:
      cpu: 2000m      # 2 CPU cores for peak loads
      memory: 2Gi

  # Persistence configuration
  persistence:
    storageClassName: "fast-ssd"  # Use appropriate storage class
    storage: 20Gi                 # Adjust based on expected message volume

  # RabbitMQ configuration
  rabbitmq:
    additionalConfig: |
      # Memory threshold (80% of available memory)
      vm_memory_high_watermark.relative = 0.8

      # Disk threshold (2GB free space)
      disk_free_limit.absolute = 2GB

      # Clustering settings
      cluster_formation.peer_discovery_backend = rabbit_peer_discovery_k8s
      cluster_formation.k8s.host = kubernetes.default.svc.cluster.local
      cluster_formation.node_cleanup.interval = 30
      cluster_formation.node_cleanup.only_log_warning = true

      # Management plugin
      management.tcp.port = 15672

      # Enable additional protocols if needed
      listeners.tcp.default = 5672

      # Logging
      log.console = true
      log.console.level = info

      # Queue master location policy
      queue_master_locator = balanced

    # Additional plugins
    additionalPlugins:

      - rabbitmq_management

      - rabbitmq_prometheus

      - rabbitmq_auth_backend_ldap  # If LDAP auth is needed

      - rabbitmq_mqtt               # If MQTT protocol is needed

      - rabbitmq_stomp              # If STOMP protocol is needed

  # Service configuration
  service:
    type: ClusterIP
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb  # For AWS

  # Monitoring
  override:
    statefulSet:
      spec:
        template:
          metadata:
            annotations:
              prometheus.io/scrape: "true"
              prometheus.io/port: "15692"
              prometheus.io/path: "/metrics"

  # Security and networking
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:

      - weight: 100

        podAffinityTerm:
          labelSelector:
            matchExpressions:

            - key: app.kubernetes.io/name

              operator: In
              values:

              - rabbitmq

          topologyKey: kubernetes.io/hostname
```

Apply the configuration:

```bash
kubectl apply -f waldur-rabbitmq-cluster.yaml
```

## Configuration for Waldur

### 1. Retrieve RabbitMQ Credentials

Get the auto-generated credentials:

```bash

# Get username

kubectl get secret waldur-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 --decode

# Get password

kubectl get secret waldur-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 --decode
```

### 2. Configure Waldur Helm Values

Update your Waldur `values.yaml`:

```yaml

# Disable the bitnami rabbitmq chart

rabbitmq:
  enabled: false
  # External RabbitMQ secret configuration
  secret:
    name: "waldur-rabbitmq-default-user"
    usernameKey: "username"
    passwordKey: "password"

# Configure external RabbitMQ connection

global:
  waldur:
    rabbitmq:
      host: "waldur-rabbitmq.default.svc.cluster.local"
      port: 5672
      vhost: "/"
```

**RabbitMQ Operator Secret Management:**

The RabbitMQ Cluster Operator automatically creates a default user secret named `[cluster-name]-default-user` containing:

- `username` - Auto-generated username

- `password` - Auto-generated password

- Other connection details

This approach avoids hardcoding credentials and follows Kubernetes security best practices.

## High Availability Configuration

For production high availability, consider these additional configurations:

### Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: waldur-rabbitmq-pdb
spec:
  minAvailable: 2  # Ensure at least 2 pods are always available
  selector:
    matchLabels:
      app.kubernetes.io/name: waldur-rabbitmq
```

### Network Policy (Optional)

Restrict network access to RabbitMQ:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: waldur-rabbitmq-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: waldur-rabbitmq
  policyTypes:

  - Ingress

  ingress:

  - from:

    - podSelector:

        matchLabels:
          app.kubernetes.io/name: waldur
    ports:

    - protocol: TCP

      port: 5672

  - from:  # Allow management interface access

    - podSelector:

        matchLabels:
          app: monitoring
    ports:

    - protocol: TCP

      port: 15672

    - protocol: TCP

      port: 15692  # Prometheus metrics
```

## Monitoring

The operator automatically enables Prometheus metrics. To access them:

1. **Prometheus Metrics Endpoint:** `<http://waldur-rabbitmq:15692/metrics`>

2. **Management UI Access:**

   ```bash
   kubectl port-forward service/waldur-rabbitmq 15672:15672
   ```

   Access at: `<http://localhost:15672`>

3. **Grafana Dashboard:** Import RabbitMQ dashboard ID `10991` or similar

## Backup and Recovery

### Automated Backup Configuration

The operator supports backup configurations through definitions:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: Backup
metadata:
  name: waldur-rabbitmq-backup
spec:
  rabbitmqClusterReference:
    name: waldur-rabbitmq
```

For production, implement external backup strategies using tools like Velero or cloud-native backup solutions.

## Scaling

Scale the cluster:

```bash
kubectl patch rabbitmqcluster waldur-rabbitmq --type='merge' -p='{"spec":{"replicas":5}}'
```

**Important:** Always use odd numbers for replicas (1, 3, 5, 7) to avoid split-brain scenarios.

## Troubleshooting

### Check Cluster Status

```bash

# Check pods

kubectl get pods -l app.kubernetes.io/name=waldur-rabbitmq

# Check cluster status

kubectl exec waldur-rabbitmq-server-0 -- rabbitmq-diagnostics cluster_status

# Check node health

kubectl exec waldur-rabbitmq-server-0 -- rabbitmq-diagnostics check_running
```

### View Logs

```bash

# View operator logs

kubectl logs -n rabbitmq-system deployment/rabbitmq-cluster-operator

# View RabbitMQ logs

kubectl logs waldur-rabbitmq-server-0
```

## Migration from Bitnami Chart

If migrating from the Bitnami chart:

1. **Backup existing data** using RabbitMQ management tools

2. **Deploy the operator** and create a new cluster

3. **Export/import** virtual hosts, users, and permissions

4. **Update Waldur configuration** to point to the new cluster

5. **Test thoroughly** before decommissioning the old setup

## Security Considerations

1. **TLS Configuration:** Enable TLS for production:

   ```yaml
   spec:
     tls:
       secretName: waldur-rabbitmq-tls
   ```

2. **Authentication:** Consider integrating with LDAP or other authentication backends

3. **Network Policies:** Implement network policies to restrict access

4. **RBAC:** Ensure appropriate Kubernetes RBAC policies are in place

## Performance Tuning

For high-throughput scenarios:

1. **Adjust memory limits** based on message volume

2. **Configure disk I/O** with appropriate storage classes

3. **Tune RabbitMQ parameters** in `additionalConfig`

4. **Monitor resource usage** and scale accordingly

## Support and Documentation

- **Official Documentation:** <https://www.rabbitmq.com/kubernetes/operator/>

- **GitHub Repository:** <https://github.com/rabbitmq/cluster-operator>

- **Examples:** <https://github.com/rabbitmq/cluster-operator/tree/main/docs/examples>

- **Community Support:** RabbitMQ Discussions on GitHub
