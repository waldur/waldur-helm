# PostgreSQL backup configuration

There are the following jobs for backups management:

- CronJob for backups creation (running by a schedule `postgresBackup.schedule`)

- CronJob for backups rotation (running by a schedule `postgresBackup.rotationSchedule`)

Backup configuration values (`postgresBackup` prefix):

- `enabled` - boolean flag for enabling/disabling backups

- `schedule` - cron-like schedule for backups

- `rotationSchedule` - cron-like schedule for backups rotation

- `maxNumber` - maximum number of backups to store

- `image` - Docker image containing the `postgres` client tools and the MinIO client (`mc`). Its Postgres major version must match the server's: `pg_dump` refuses to dump a newer server

  ([opennode/postgres-minio](https://hub.docker.com/r/opennode/postgres-minio)
  by default; its `17` tag is rebuilt weekly in place, and `imagePullPolicy`
  (default `Always`) makes every job run pick up the rebuild)

## Backup storage

Backups go to an S3-compatible bucket (`backupStorage` prefix). The jobs use the
`mc` client, so MinIO, AWS S3, Ceph RGW and similar endpoints all work:

- `endpoint` - S3 endpoint URL, e.g. `http://minio.default.svc.cluster.local:9000`

- `bucketName` - bucket the backups are written to (under `backups/postgres/`)

- `existingSecret.name` - name of a Secret in the release namespace holding the
  S3 credentials. When set, the backup, rotation and restore pods read the
  credentials from it with `secretKeyRef`, and `accessKey`/`secretKey` are ignored

- `existingSecret.accessKeyKey` - key of the access key in that Secret
  (default `AWS_ACCESS_KEY_ID`)

- `existingSecret.secretKeyKey` - key of the secret key in that Secret
  (default `AWS_SECRET_ACCESS_KEY`)

- `accessKey`, `secretKey` - plain credentials, used only when
  `existingSecret.name` is empty. They end up as plain environment values in
  the CronJob and Deployment specs, readable by anyone who can read those
  objects, so prefer `existingSecret` in production

The default key names match the Secret that a Rook or NooBaa ObjectBucketClaim
generates, so such a Secret can be referenced directly. Otherwise create one:

```bash
kubectl create secret generic waldur-backup-s3 \
  --from-literal=AWS_ACCESS_KEY_ID='<access key>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<secret key>'
```

```yaml
postgresBackup:
  enabled: true

backupStorage:
  endpoint: "https://s3.example.com"
  bucketName: "waldur-backups"
  existingSecret:
    name: waldur-backup-s3
```

## Backups restoration

To restore backups you need to connect to the restoration pod. The major prerequisite for this is stopping the
Waldur backend pods to avoid errors. **NB: During restoration process, the site will be unavailable**. For this,
please execute the following lines in the Kubernetes node:

```bash

# Stop all the API pods

kubectl scale --replicas=0 deployment/waldur-mastermind-api

# Stop all the Celery worker pods

kubectl scale --replicas=0 deployment/waldur-mastermind-worker

# Connect to the restoration pod

kubectl exec -it deployment/waldur-db-restore -- bash
```

This will give you access to a terminal of a restoration pod. In this shell, please, execute the command:

```bash
db-backup-minio-auth
```

This will print the recent 5 backups available for restoration. Example:

```bash
root@waldur-db-restore-ff7f586bb-nb8jt:/# db-backup-minio-auth
[+] LOCAL_PG_BACKUPS_DIR :
[+] MINIO_PG_BACKUPS_DIR : pg/data/backups/postgres
[+] Setting up the postgres alias for minio server (<http://minio.default.svc.cluster.local:9000)>
[+] Last 5 backups
[2022-12-01 05:00:02 UTC]  91KiB backup-2022-12-01-05-00.sql.gz
[2022-11-30 05:00:02 UTC]  91KiB backup-2022-11-30-05-00.sql.gz
[2022-11-29 05:00:02 UTC]  91KiB backup-2022-11-29-05-00.sql.gz
[2022-11-28 16:30:37 UTC]  91KiB backup-2022-11-28-16-30.sql.gz
[2022-11-28 16:28:27 UTC]  91KiB backup-2022-11-28-16-28.sql.gz
[+] Finished
```

As you can see, the backup name contains the date and time when it was created in `YYYY-mm-dd-HH-MM` format. You can freely choose the one you need.

```bash
  db-backup-minio-auth
  export BACKUP_FILENAME=<SELECTED_BACKUP>
  mc cp pg/$MINIO_BUCKET/backups/postgres/$BACKUP_FILENAME backup.sql.gz
  gzip -d backup.sql.gz
  # Be careful: the next lines have potentially danger operations
  psql -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'waldur' AND pid <> pg_backend_pid();"
  psql -d postgres -c 'DROP DATABASE waldur;'
  createdb waldur
  psql -f backup.sql
  rm backup.sql
```

## Restoration from external backup

If you want to use a pre-created backup from an external system, copy the backup file:

1. Copy the backup file to your local machine

2. Copy the file to pod

    ```bash
    export RESTORATION_POD_NAME=$(kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep restore)
    kubectl cp <BACKUP_FILE> $RESTORATION_POD_NAME:/tmp/backup.sql.gz
    ```

3. Connect to pod's terminal

    ```bash
    kubectl exec -it $RESTORATION_POD_NAME -- bash
    ```

4. Apply the backup

    ```bash
    gzip -d /tmp/backup.sql.gz
    # Be careful: the next lines have potentially danger operations
    psql -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'waldur' AND pid <> pg_backend_pid();"
    psql -d postgres -c 'DROP DATABASE waldur;'
    createdb waldur
    psql -f /tmp/backup.sql
    rm /tmp/backup.sql
    ```
