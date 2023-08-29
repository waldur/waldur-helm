# External DB integration

Waldur Helm can use an external PostgreSQL deployed within the same Kubernetes cluster.

For this, you need to set the following variables in `values.yaml`:

1. `externalDB.enabled` - toggler for integration; requires `postgresql.enabled` and `postgresqlha.enabled` to be `false`
2. `externalDB.flavor` - a type of the DB management system; currently only `zalando` ([Zalando operator](https://postgres-operator.readthedocs.io/en/latest/)) is supported
3. `externalDB.secretName` - name of the secret with PostgreSQL credentials for Waldur user; should include `username` and `password` keys
4. `externalDB.serviceName` - name of the service linked to PostgreSQL master

Zalando-managed PostgreSQL cluster example:

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: waldur-postgresql-<UNIQUE_SUFFIX_EG_CURRENT_DATE>
spec:
  teamId: "waldur"
  volume:
    size: 20Gi
  numberOfInstances: 2
  users:
    waldur:
    - superuser
    - createdb
  databases:
    waldur: waldur
  postgresql:
    version: "14"
  resources:
    requests:
      cpu: '500m'
      memory: 500Mi
    limits:
      cpu: '1'
      memory: 2Gi
```

## Backup setup

Enable backups for a cluster with the following addition to a manifest file:

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: waldur-postgresql-<UNIQUE_SUFFIX_EG_CURRENT_DATE>
spec:
  # ...
  env:
    - name: AWS_ENDPOINT # S3-like storage endpoint
      valueFrom:
        secretKeyRef:
          key: URL
          name: postgres-cluster-backups-minio
    - name: AWS_ACCESS_KEY_ID # Username for S3-like storage
      valueFrom:
        secretKeyRef:
          key: username
          name: postgres-cluster-backups-minio
    - name: AWS_SECRET_ACCESS_KEY # Password for the storage
      valueFrom:
        secretKeyRef:
          key: password
          name: postgres-cluster-backups-minio
    - name: WAL_S3_BUCKET # Bucket name for the storage
      valueFrom:
        secretKeyRef:
          key: bucket
          name: postgres-cluster-backups-minio
    - name: USE_WALG_BACKUP # Enable backups to the storage
      value: 'true'
    - name: USE_WALG_RESTORE # Enable restore for replicas using the storage
      value: 'true'
    - name: BACKUP_SCHEDULE # Base backups schedule
      value: "0 2 * * *"
```

You also need to create a secret file with the credentials for the storage:

```yaml
# puhuri-core-dev
apiVersion: v1
kind: Secret
metadata:
  name: postgres-cluster-backups-minio
type: Opaque
data:
  URL: "B64_ENCODED_ENDPOINT"
  username: "B64_ENCODED_USERNAME"
  password: "B64_ENCODED_PASSWORD"
  bucket: "B64_ENCODED_BUCKET"

```

### Trigger a base backup manually

Connect to the leader PSQL pod and execute the following commands:

```bash
su postgres
envdir "/run/etc/wal-e.d/env" /scripts/postgres_backup.sh "/home/postgres/pgdata/pgroot/data"
# Output:
# ...
# INFO: 2023/08/24 10:27:05.159175 Wrote backup with name base_00000009000000010000009C
envdir "/run/etc/wal-e.d/env" wal-g backup-list
# Output:
# name                          modified             wal_segment_backup_start
# ...
# base_00000009000000010000009C 2023-08-24T10:27:05Z 00000009000000010000009C
```

## Restore DB from backup

The preferable option is creation a new instance of PostgreSQL cluster cloning data from the original one.

For this, create a manifest with the following content:

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: waldur-postgresql-<UNIQUE_SUFFIX_EG_CURRENT_DATE>
spec:
  clone:
    cluster: "waldur-postgresql-<SUFFIX>" # Name of a reference cluster
    timestamp: "2023-08-24T14:23:00+03:00" # Desired db snapshot time
    s3_wal_path: "s3://puhuri-core-dev/spilo/puhuri-core-dev-waldur-postgresql/wal/" # Path to a directory with WALs in S3 bucket
    s3_force_path_style: true # Use the path above
    env:
    # ...
    - name: CLONE_METHOD # Enable clone
      value: "CLONE_WITH_WALE"
    - name: CLONE_AWS_ENDPOINT # S3-like storage endpoint
      valueFrom:
        secretKeyRef:
          key: URL
          name: postgres-cluster-backups-minio
    - name: CLONE_AWS_ACCESS_KEY_ID # Username for S3-like storage
      valueFrom:
        secretKeyRef:
          key: username
          name: postgres-cluster-backups-minio
    - name: CLONE_AWS_SECRET_ACCESS_KEY # Password for the storage
      valueFrom:
        secretKeyRef:
          key: password
          name: postgres-cluster-backups-minio
```

Then, apply the manifest to the cluster, change `externalDB.{secretName, serviceName}` after DB bootstrap and upgrade Waldur release.
