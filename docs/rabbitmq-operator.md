# RabbitMQ Cluster Operator (Production)

For **production deployments**, it is strongly recommended to use the official [RabbitMQ Cluster Kubernetes Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview) instead of the Bitnami Helm chart. The operator provides better lifecycle management, high availability, and production-grade features.

> **The bundled Bitnami subchart is stuck on RabbitMQ 4.1 and cannot be upgraded.**
> The chart's `rabbitmq` dependency pulls `bitnamilegacy/rabbitmq`, a registry
> that's frozen at `4.1.3-debian-12-r1` — no `4.2.x`/`4.3.x` tags exist
> (confirmed via `docker manifest inspect` against several candidate tags on
> 2026-08-03, and reproduced in-cluster: `helm install` with a bumped
> `rabbitmq.image.tag` leaves the RabbitMQ pod in `ImagePullBackOff`/
> `ErrImagePull` — `... not found`). Since RabbitMQ 4.1 loses community
> support in January 2026 and 4.2 reaches EOL July 31, 2026, the bundled
> subchart cannot be the long-term path for any deployment. This is why
> `waldur/test/values.yaml` (CI's test install target) now points at an
> operator-managed cluster instead of the subchart. Migrating the bundled
> subchart itself off the frozen registry — to a different chart/image
> entirely — is tracked as separate future work, not part of this
> compatibility fix.

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

## Version upgrade path

RabbitMQ does not support skipping a minor version. From the upstream
[upgrade guide](https://www.rabbitmq.com/docs/upgrade): *"Upgrading to `4.3.x` is
only possible from `4.2.x`."* The supported steps are `4.1.x → 4.2.x` and
`4.2.x → 4.3.x`; there is no `4.1.x → 4.3.x` path. A cluster on 4.1 must therefore
be walked through 4.2, rolling and verifying at each step, rather than jumped
straight to 4.3.

Before each step:

- **Enable all stable feature flags.** The upgrade guide is explicit that *"all
  stable feature flags must be enabled before an upgrade, or the upgrade may
  fail"*. This is not hypothetical — a default 4.1 node has `khepri_db` disabled,
  and 4.3 requires it.

  ```bash
  kubectl exec -n <namespace> <cluster-name>-server-0 -- rabbitmqctl enable_feature_flag all
  kubectl exec -n <namespace> <cluster-name>-server-0 -- rabbitmqctl list_feature_flags
  ```

- **Check the Erlang requirement.** RabbitMQ `4.3.3` and later require Erlang 27,
  and nodes fail to start on anything older. The official `rabbitmq:4.3.x` container
  images already ship OTP 27, so this only affects package-based installations.

Bump `spec.image` one minor series at a time and let the operator roll the
StatefulSet, waiting for `AllReplicasReady` before starting the next step:

```bash
kubectl wait --for=condition=AllReplicasReady --timeout=600s rabbitmqcluster/<cluster-name>
```

## Installation

### 1. Install the RabbitMQ Cluster Operator

```bash
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.22.5/cluster-operator.yml
```

Pin the version rather than using `latest`: the operator is cluster-scoped, so an
unpinned re-apply upgrades it for every `RabbitmqCluster` on the cluster at once.

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
  # Pin explicitly -- an unset image field silently takes whatever the
  # operator's default is, rather than a deliberate version.
  image: rabbitmq:4.3.5

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

      # Queue leader location policy (queue_master_locator is deprecated)
      queue_leader_locator = balanced

      # RabbitMQ 4.3 compatibility: 4.3 denies transient, non-exclusive
      # queues by default, the combination kombu's pidbox and Celery's
      # gossip queues declare. Mastermind now declares both exclusive
      # (CELERY_CONTROL_QUEUE_EXCLUSIVE / CELERY_EVENT_QUEUE_EXCLUSIVE), so
      # this flag is only needed while the deployed Waldur image predates
      # that change. It is read at node boot and is accepted on 4.1, 4.2 and
      # 4.3 alike, so it can be set or removed at any point in the walk.
      deprecated_features.permit.transient_nonexcl_queues = true

    # Additional plugins
    additionalPlugins:

      - rabbitmq_management

      - rabbitmq_prometheus

      - rabbitmq_auth_backend_ldap  # If LDAP auth is needed

      - rabbitmq_stomp              # If STOMP protocol is needed

      - rabbitmq_web_stomp          # Required for Waldur's websocket-STOMP ingress

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

# Disable the bundled rabbitmq subchart and point the chart at the
# operator-managed cluster. `host` must match the RabbitmqCluster name -- the
# operator creates a Service of that name -- and the secret is the one the
# operator generates as `<cluster-name>-default-user`.

rabbitmq:
  enabled: false
  host: "waldur-rabbitmq"
  secret:
    name: "waldur-rabbitmq-default-user"
    usernameKey: "username"
    passwordKey: "password"
```

> **Do not set `global.waldur.rabbitmq.*`.** The chart does not read those keys;
> the broker host comes from the top-level `rabbitmq.host` value
> (`templates/_helpers.tpl`, `waldur.rabbitmq.rmqHost`). Setting only the
> `global.*` form leaves `rabbitmq.host` at its default of `rmq-rabbitmq` — the
> name of the old Bitnami release — and the deployment points at a Service that
> does not exist.

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
