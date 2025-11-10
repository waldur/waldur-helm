# PostgreSQL Operators (Production)

For **production deployments**, it is strongly recommended to use a PostgreSQL operator instead of the Bitnami Helm charts. This document covers two production-ready options:

1. **CloudNativePG** (Recommended for new deployments)

2. **Zalando PostgreSQL Operator** (For existing deployments or specific use cases)

## Operator Selection Guide

### CloudNativePG ⭐ *Recommended for New Deployments*

**Best for:**

- New production deployments

- Modern Kubernetes-native environments

- Teams wanting the latest PostgreSQL features

- Organizations requiring active development and community support

**Pros:**

- Most popular PostgreSQL operator in 2024 (27.6% market share)

- Active development and community

- Modern Kubernetes-native architecture

- Comprehensive backup and recovery with Barman

- Built-in monitoring and observability

- Strong enterprise backing from EDB

### Zalando PostgreSQL Operator

**Best for:**

- Existing deployments already using Zalando

- Teams with specific Patroni requirements

- Multi-tenant environments

- Organizations comfortable with stable but less actively developed tools

**Pros:**

- Battle-tested in production environments

- Built on proven Patroni technology

- Excellent multi-tenancy support

- Mature and stable codebase

**Considerations:**

- Limited active development since 2021

- May lag behind in supporting latest PostgreSQL versions

- Less community engagement compared to CloudNativePG

---

## Option 1: CloudNativePG (Recommended)

## Overview

CloudNativePG provides:

- Kubernetes-native PostgreSQL cluster management

- Automated failover and self-healing capabilities

- Built-in streaming replication and high availability

- Continuous backup with Point-in-Time Recovery (PITR)

- Integrated monitoring with Prometheus

- Zero-downtime maintenance operations

- Multi-cloud and hybrid cloud support

## Prerequisites

- Kubernetes cluster version 1.25 or above

- Configured `kubectl` access

- Appropriate RBAC permissions

- Storage class with persistent volume support

## Installation

### 1. Install CloudNativePG Operator

```bash

# Install the latest release

kubectl apply -f <https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.23/releases/cnpg-1.23.0.yaml>
```

Verify the operator is running:

```bash
kubectl get pods -n cnpg-system
```

### 2. Create a Production PostgreSQL Cluster

Create a production-ready PostgreSQL cluster configuration:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: waldur-postgres
  namespace: default
spec:
  # High availability setup
  instances: 3  # 1 primary + 2 replicas

  # PostgreSQL version
  imageName: ghcr.io/cloudnative-pg/postgresql:16.4

  # Bootstrap configuration
  bootstrap:
    initdb:
      database: waldur
      owner: waldur
      secret:
        name: waldur-postgres-credentials

  # Resource configuration
  resources:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

  # Storage configuration
  storage:
    size: 100Gi
    storageClass: "fast-ssd"  # Use appropriate storage class

  # PostgreSQL configuration
  postgresql:
    parameters:
      # Performance tuning
      shared_buffers: "512MB"
      effective_cache_size: "3GB"
      maintenance_work_mem: "256MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"

      # Connection settings
      max_connections: "200"

      # Logging
      log_destination: "stderr"
      log_statement: "all"
      log_duration: "on"
      log_line_prefix: "%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h "

      # Replication settings
      max_wal_senders: "10"
      max_replication_slots: "10"

      # Archive settings
      archive_mode: "on"
      archive_command: "/bin/true"  # Will be overridden by backup configuration

  # Monitoring configuration
  monitoring:
    enabled: true
    prometheusRule:
      enabled: true

  # Backup configuration
  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: "s3://your-backup-bucket/waldur-postgres"
      s3Credentials:
        accessKeyId:
          name: backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-credentials
          key: SECRET_ACCESS_KEY
      wal:
        retention: "7d"
      data:
        retention: "30d"
        jobs: 1

  # Affinity rules for high availability
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:

      - weight: 100

        podAffinityTerm:
          labelSelector:
            matchLabels:
              postgresql: waldur-postgres
          topologyKey: kubernetes.io/hostname

  # Connection pooling with PgBouncer
  pooler:
    enabled: true
    instances: 2
    type: pgbouncer
    pgbouncer:
      poolMode: transaction
      parameters:
        max_client_conn: "200"
        default_pool_size: "25"
        min_pool_size: "5"
        reserve_pool_size: "5"
        server_reset_query: "DISCARD ALL"
```

### 3. Create Required Secrets

Create database credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: waldur-postgres-credentials
type: kubernetes.io/basic-auth
stringData:
  username: waldur
  password: "your-secure-password"  # Use a strong password
```

Create backup credentials (for S3-compatible storage):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backup-credentials
type: Opaque
stringData:
  ACCESS_KEY_ID: "your-access-key"
  SECRET_ACCESS_KEY: "your-secret-key"
```

Apply the configurations:

```bash
kubectl apply -f waldur-postgres-credentials.yaml
kubectl apply -f backup-credentials.yaml
kubectl apply -f waldur-postgres-cluster.yaml
```

## Configuration for Waldur

### 1. Retrieve Connection Information

The operator automatically creates services for the cluster:

- **Read-Write Service:** `waldur-postgres-rw` (primary database)

- **Read-Only Service:** `waldur-postgres-ro` (replica databases)

- **PgBouncer Service:** `waldur-postgres-pooler-rw` (connection pooler)

### 2. Configure Waldur Helm Values

Update your Waldur `values.yaml`:

```yaml

# Disable bitnami postgresql charts

postgresql:
  enabled: false
postgresqlha:
  enabled: false

# Configure external PostgreSQL connection

externalDB:
  enabled: true
  secretName: "waldur-postgres-app"  # CloudNativePG auto-generated secret
  serviceName: "waldur-postgres-pooler-rw"  # Use pooler for better performance
```

## High Availability Features

### Automatic Failover

CloudNativePG provides automatic failover:

- Monitors primary instance health

- Automatically promotes replica to primary on failure

- Updates service endpoints automatically

- Zero-data-loss failover with synchronous replication

### Replica Configuration

For read scaling and high availability:

```yaml
spec:
  instances: 5  # 1 primary + 4 replicas

  # Configure synchronous replication for zero data loss
  postgresql:
    synchronous:
      method: "first"
      number: 1  # Number of sync replicas
```

## Backup and Recovery

### Scheduled Backups

Create a scheduled backup:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: waldur-postgres-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  backupOwnerReference: "self"
  cluster:
    name: waldur-postgres
```

### Manual Backup

Trigger a manual backup:

```bash
kubectl cnpg backup waldur-postgres
```

### Point-in-Time Recovery

Create a new cluster from a specific point in time:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: waldur-postgres-recovery
spec:
  instances: 3

  bootstrap:
    recovery:
      source: waldur-postgres
      recoveryTarget:
        targetTime: "2024-10-31 14:30:00"  # Specific timestamp

  externalClusters:

  - name: waldur-postgres

    barmanObjectStore:
      destinationPath: "s3://your-backup-bucket/waldur-postgres"
      s3Credentials:
        accessKeyId:
          name: backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-credentials
          key: SECRET_ACCESS_KEY
```

## Monitoring and Observability

### Prometheus Integration

The operator exports metrics automatically. Access them via:

- **Metrics endpoint:** `<http://waldur-postgres-any:9187/metrics`>

- **Custom metrics:** Can be configured via SQL queries

### Grafana Dashboard

Import the official CloudNativePG Grafana dashboard:

- Dashboard ID: `20417` (CloudNativePG Dashboard)

### Health Checks

Monitor cluster health:

```bash

# Check cluster status

kubectl get cluster waldur-postgres

# Check instances

kubectl get instances

# Check backups

kubectl get backups

# View detailed cluster info

kubectl describe cluster waldur-postgres
```

## Scaling Operations

### Horizontal Scaling

Scale replicas:

```bash

# Scale up to 5 instances

kubectl patch cluster waldur-postgres --type='merge' -p='{"spec":{"instances":5}}'

# Scale down to 3 instances

kubectl patch cluster waldur-postgres --type='merge' -p='{"spec":{"instances":3}}'
```

### Vertical Scaling

Update resources:

```bash
kubectl patch cluster waldur-postgres --type='merge' -p='{"spec":{"resources":{"requests":{"memory":"4Gi","cpu":"2000m"},"limits":{"memory":"8Gi","cpu":"4000m"}}}}'
```

## Maintenance Operations

### PostgreSQL Major Version Upgrade

Update the PostgreSQL version:

```yaml
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:17.0  # New version

  # Configure upgrade strategy
  primaryUpdateStrategy: unsupervised  # or supervised for manual control
```

### Operator Upgrade

Upgrade the operator:

```bash
kubectl apply -f <https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml>
```

## Security Configuration

### TLS Encryption

Enable TLS for client connections:

```yaml
spec:
  certificates:
    serverTLSSecret: "waldur-postgres-tls"
    serverCASecret: "waldur-postgres-ca"
    clientCASecret: "waldur-postgres-client-ca"
    replicationTLSSecret: "waldur-postgres-replication-tls"
```

### Network Policies

Restrict database access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: waldur-postgres-netpol
spec:
  podSelector:
    matchLabels:
      postgresql: waldur-postgres
  policyTypes:

  - Ingress

  ingress:

  - from:

    - podSelector:

        matchLabels:
          app.kubernetes.io/name: waldur
    ports:

    - protocol: TCP

      port: 5432

  - from:  # Allow monitoring

    - podSelector:

        matchLabels:
          app: monitoring
    ports:

    - protocol: TCP

      port: 9187
```

## Troubleshooting

### Common Commands

```bash

# Check cluster logs

kubectl logs -l postgresql=waldur-postgres

# Check operator logs

kubectl logs -n cnpg-system deployment/cnpg-controller-manager

# Connect to primary database

kubectl exec -it waldur-postgres-1 -- psql -U waldur

# Check replication status

kubectl cnpg status waldur-postgres

# Promote a replica manually (if needed)

kubectl cnpg promote waldur-postgres-2
```

### Performance Monitoring

```bash

# Check slow queries

kubectl exec -it waldur-postgres-1 -- psql -U waldur -c "SELECT query, mean_exec_time, calls FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Check connections

kubectl exec -it waldur-postgres-1 -- psql -U waldur -c "SELECT count(*) FROM pg_stat_activity;"

# Check replication lag

kubectl exec -it waldur-postgres-1 -- psql -U waldur -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

## Migration from Bitnami Chart

To migrate from the Bitnami PostgreSQL chart:

1. **Backup existing data** using `pg_dump`

2. **Deploy CloudNativePG cluster** with new name

3. **Restore data** using `pg_restore`

4. **Update Waldur configuration** to use new cluster

5. **Test thoroughly** before decommissioning old setup

Example migration script:

```bash

# Backup from old cluster

kubectl exec -it postgresql-primary-0 -- pg_dump -U waldur waldur > waldur_backup.sql

# Restore to new cluster

kubectl exec -i waldur-postgres-1 -- psql -U waldur waldur < waldur_backup.sql
```

## Performance Tuning

### Database Optimization

For high-performance scenarios:

```yaml
spec:
  postgresql:
    parameters:
      # Increase shared buffers (25% of RAM)
      shared_buffers: "1GB"

      # Increase effective cache size (75% of RAM)
      effective_cache_size: "3GB"

      # Optimize for SSD storage
      random_page_cost: "1.1"
      effective_io_concurrency: "200"

      # Connection and memory settings
      max_connections: "300"
      work_mem: "16MB"
      maintenance_work_mem: "512MB"

      # WAL optimization
      wal_buffers: "32MB"
      checkpoint_completion_target: "0.9"
      max_wal_size: "4GB"
      min_wal_size: "1GB"
```

### Connection Pooling Optimization

```yaml
spec:
  pooler:
    pgbouncer:
      parameters:
        pool_mode: "transaction"
        max_client_conn: "500"
        default_pool_size: "50"
        min_pool_size: "10"
        reserve_pool_size: "10"
        max_db_connections: "100"
        server_lifetime: "3600"
        server_idle_timeout: "600"
```

## Support and Documentation

- **Official Documentation:** <https://cloudnative-pg.io/documentation/>

- **GitHub Repository:** <https://github.com/cloudnative-pg/cloudnative-pg>

- **Community Slack:** #cloudnativepg on Kubernetes Slack

- **Tutorials:** <https://cloudnative-pg.io/documentation/current/tutorial/>

- **Best Practices:** <https://cloudnative-pg.io/documentation/current/appendices/>

---

## Option 2: Zalando PostgreSQL Operator

## Overview

The Zalando PostgreSQL operator is a mature, battle-tested solution built on Patroni technology. It provides automated PostgreSQL cluster management with proven stability in production environments.

**Key Features:**

- Built on Patroni for high availability

- Multi-tenant optimized

- Proven production reliability

- Manifest-based configuration

- Integration with existing Zalando tooling

**Current Status (2024):**

- Stable and mature codebase

- Limited active development since 2021

- Suitable for existing deployments and specific use cases

## Prerequisites

- Kubernetes cluster version 1.16 or above

- Configured `kubectl` access

- Appropriate RBAC permissions

## Installation

### 1. Install Zalando PostgreSQL Operator

```bash

# Clone the repository

git clone <https://github.com/zalando/postgres-operator.git>
cd postgres-operator

# Apply the operator manifests

kubectl apply -k manifests/
```

Or using Helm:

```bash

# Add Zalando charts repository

helm repo add postgres-operator-charts <https://opensource.zalando.com/postgres-operator/charts/postgres-operator/>

# Install the operator

helm install postgres-operator postgres-operator-charts/postgres-operator
```

Verify the operator is running:

```bash
kubectl get pods -n default -l name=postgres-operator
```

### 2. Create a Production PostgreSQL Cluster

Create a production-ready PostgreSQL cluster:

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: waldur-postgres-zalando
  namespace: default
spec:
  teamId: "waldur"

  # High availability setup
  numberOfInstances: 3

  # PostgreSQL version
  postgresql:
    version: "16"
    parameters:
      # Performance tuning
      shared_buffers: "512MB"
      effective_cache_size: "3GB"
      maintenance_work_mem: "256MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      max_connections: "200"

      # Logging
      log_statement: "all"
      log_duration: "on"
      log_line_prefix: "%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h "

  # Resource configuration
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

  # Storage configuration
  volume:
    size: "100Gi"
    storageClass: "fast-ssd"

  # Users and databases
  users:
    waldur:

      - superuser

      - createdb

    readonly:

      - login

  databases:
    waldur: waldur

  # Backup configuration
  env:

    - name: USE_WALG_BACKUP

      value: "true"

    - name: USE_WALG_RESTORE

      value: "true"

    - name: BACKUP_SCHEDULE

      value: "0 2 * * *"  # Daily at 2 AM

    - name: AWS_ENDPOINT

      valueFrom:
        secretKeyRef:
          key: endpoint
          name: postgres-backup-credentials

    - name: AWS_ACCESS_KEY_ID

      valueFrom:
        secretKeyRef:
          key: access_key_id
          name: postgres-backup-credentials

    - name: AWS_SECRET_ACCESS_KEY

      valueFrom:
        secretKeyRef:
          key: secret_access_key
          name: postgres-backup-credentials

    - name: WAL_S3_BUCKET

      valueFrom:
        secretKeyRef:
          key: bucket
          name: postgres-backup-credentials

  # Pod disruption budget
  enableMasterLoadBalancer: false
  enableReplicaLoadBalancer: false

  # Connection pooling
  connectionPooler:
    numberOfInstances: 2
    mode: "transaction"
    parameters:
      max_client_conn: "200"
      default_pool_size: "25"
```

### 3. Create Required Secrets

Create backup credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-backup-credentials
type: Opaque
stringData:
  endpoint: "<https://your-s3-endpoint.com">
  access_key_id: "your-access-key"
  secret_access_key: "your-secret-key"
  bucket: "waldur-postgres-backups"
```

Apply the configurations:

```bash
kubectl apply -f postgres-backup-credentials.yaml
kubectl apply -f waldur-postgres-zalando.yaml
```

## Configuration for Waldur

### 1. Retrieve Connection Information

The Zalando operator creates services with specific naming:

- **Master Service:** `waldur-postgres-zalando` (read-write)

- **Replica Service:** `waldur-postgres-zalando-repl` (read-only)

- **Connection Pooler:** `waldur-postgres-zalando-pooler` (if enabled)

Get the credentials from the generated secret:

```bash

# Get the secret name (follows pattern: {username}.{cluster-name}.credentials.postgresql.acid.zalan.do)

kubectl get secrets | grep waldur-postgres-zalando

# Get credentials

kubectl get secret waldur.waldur-postgres-zalando.credentials.postgresql.acid.zalan.do -o jsonpath='{.data.password}' | base64 --decode
```

### 2. Configure Waldur Helm Values

Update your Waldur `values.yaml`:

```yaml

# Disable bitnami postgresql charts

postgresql:
  enabled: false
postgresqlha:
  enabled: false

# Configure external PostgreSQL connection

externalDB:
  enabled: true
  host: "waldur-postgres-zalando.default.svc.cluster.local"
  port: 5432
  database: "waldur"
  secretName: "waldur.waldur-postgres-zalando.credentials.postgresql.acid.zalan.do"
  serviceName: "waldur-postgres-zalando"

  # Optional: Configure read-only connection
  readonlyHost: "waldur-postgres-zalando-repl.default.svc.cluster.local"
```

## High Availability Features

### Automatic Failover

Zalando operator uses Patroni for automatic failover:

- Continuous health monitoring of PostgreSQL instances

- Automatic promotion of replicas on primary failure

- Distributed consensus for leader election

- Minimal downtime during failover scenarios

### Zalando Scaling Operations

Scale the cluster:

```bash
kubectl patch postgresql waldur-postgres-zalando --type='merge' -p='{"spec":{"numberOfInstances":5}}'
```

## Backup and Recovery

### Manual Backup

Trigger a manual backup:

```bash

# Connect to the master pod

kubectl exec -it waldur-postgres-zalando-0 -- bash

# Run backup

su postgres
envdir "/run/etc/wal-e.d/env" /scripts/postgres_backup.sh "/home/postgres/pgdata/pgroot/data"

# List backups

envdir "/run/etc/wal-e.d/env" wal-g backup-list
```

### Point-in-Time Recovery

Create a new cluster from backup:

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: waldur-postgres-recovery
spec:
  clone:
    cluster: "waldur-postgres-zalando"
    timestamp: "2024-10-31T14:23:00+03:00"
    s3_wal_path: "s3://waldur-postgres-backups/spilo/waldur-postgres-zalando/wal/"
    s3_force_path_style: true
  env:

    - name: CLONE_METHOD

      value: "CLONE_WITH_WALE"

    - name: CLONE_AWS_ENDPOINT

      valueFrom:
        secretKeyRef:
          key: endpoint
          name: postgres-backup-credentials

    - name: CLONE_AWS_ACCESS_KEY_ID

      valueFrom:
        secretKeyRef:
          key: access_key_id
          name: postgres-backup-credentials

    - name: CLONE_AWS_SECRET_ACCESS_KEY

      valueFrom:
        secretKeyRef:
          key: secret_access_key
          name: postgres-backup-credentials
```

## Monitoring

### Prometheus Integration

Enable monitoring by adding sidecars:

```yaml
spec:
  sidecars:

    - name: "postgres-exporter"

      image: "prometheuscommunity/postgres-exporter:latest"
      ports:

        - name: exporter

          containerPort: 9187
      env:

        - name: DATA_SOURCE_NAME

          value: "postgresql://waldur@localhost:5432/postgres?sslmode=disable"
```

### Health Checks

Monitor cluster status:

```bash

# Check cluster status

kubectl get postgresql waldur-postgres-zalando

# Check pods

kubectl get pods -l cluster-name=waldur-postgres-zalando

# Check services

kubectl get services -l cluster-name=waldur-postgres-zalando

# View cluster details

kubectl describe postgresql waldur-postgres-zalando
```

## Maintenance Operations

### PostgreSQL Version Upgrade

Update PostgreSQL version:

```yaml
spec:
  postgresql:
    version: "17"  # Upgrade to newer version
```

**Note:** Major version upgrades may require manual intervention and testing.

### Operator Upgrade

Update the operator:

```bash
kubectl apply -k manifests/
```

## Troubleshooting

### Common Commands

```bash

# Check operator logs

kubectl logs -l name=postgres-operator

# Check cluster logs

kubectl logs waldur-postgres-zalando-0

# Connect to database

kubectl exec -it waldur-postgres-zalando-0 -- psql -U waldur

# Check Patroni status

kubectl exec -it waldur-postgres-zalando-0 -- patronictl list

# Check replication status

kubectl exec -it waldur-postgres-zalando-0 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Common Issues

1. **Cluster not starting:** Check resource limits and storage class

2. **Backup failures:** Verify S3 credentials and permissions

3. **Connection issues:** Check service names and network policies

4. **Failover issues:** Review Patroni logs and cluster configuration

## Migration Between Operators

### From Zalando to CloudNativePG

1. **Backup data** from Zalando cluster using `pg_dump`

2. **Deploy CloudNativePG cluster**

3. **Restore data** using `pg_restore`

4. **Update Waldur configuration**

5. **Decommission Zalando cluster** after verification

### From CloudNativePG to Zalando

Similar process but with attention to:

- Different backup formats and restore procedures

- Configuration parameter mapping

- Service naming conventions

## Support and Documentation

- **Official Documentation:** <https://postgres-operator.readthedocs.io/>

- **GitHub Repository:** <https://github.com/zalando/postgres-operator>

- **Patroni Documentation:** <https://patroni.readthedocs.io/>

- **Community:** GitHub Issues and Discussions

---

## Comparison Summary

| Feature | CloudNativePG | Zalando Operator |
|---------|---------------|------------------|
| **Development Status** | ✅ Active (2024) | ⚠️ Maintenance mode |
| **Community** | ✅ Growing rapidly | ⚠️ Established but less active |
| **Kubernetes Native** | ✅ True Kubernetes-native | ⚠️ Patroni-based |
| **Backup/Recovery** | ✅ Barman integration | ✅ WAL-G/WAL-E |
| **Monitoring** | ✅ Built-in Prometheus | ⚠️ Requires sidecars |
| **Multi-tenancy** | ⚠️ Basic | ✅ Excellent |
| **Production Readiness** | ✅ Proven and growing | ✅ Battle-tested |
| **Learning Curve** | ✅ Moderate | ⚠️ Steeper (Patroni knowledge) |
| **Enterprise Support** | ✅ EDB backing | ⚠️ Community only |

## Recommendation

- **New deployments:** Choose CloudNativePG for modern Kubernetes-native architecture and active development

- **Existing Zalando deployments:** Continue with Zalando if stable, consider migration planning for long-term

- **Multi-tenant requirements:** Zalando may be better suited

- **Latest PostgreSQL features:** CloudNativePG provides faster adoption
