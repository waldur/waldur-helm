# PostgreSQL backup configuration

There are the following jobs for backups management:

- CronJob for backups creation (running by a schedule `postgresBackup.schedule`)

- CronJob for backups rotation (running by a schedule `postgresBackup.rotationSchedule`)

Backup configuration values (`postgresBackup` prefix):

- `enabled` - boolean flag for enabling/disabling backups

- `schedule` - cron-like schedule for backups

- `rotationSchedule` - cron-like schedule for backups rotation

- `maxNumber` - maximum number of backups to store

- `image` - Docker image containing `potgres` and `minio` (client) binaries
  ([opennode/postgres-minio](https://hub.docker.com/r/opennode/postgres-minio)
  by default)

## Backups restoration

To restore backups you need to:

1. Connect to the restoration pod. The major prerequisite for this is stopping the Waldur backend pods to avoid errors. **NB: During restoration process, the site will be unavailable**. For this, please execute the following lines in the Kubernetes node:

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
[+] Setting up the postgres alias for minio server (http://minio.default.svc.cluster.local:9000)
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
1. Copy the file to pod

    ```bash
    export RESTORATION_POD_NAME=$(kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep restore)
    kubectl cp <BACKUP_FILE> $RESTORATION_POD_NAME:/tmp/backup.sql.gz
    ```

1. Connect to pod's terminal

    ```bash
    kubectl exec -it $RESTORATION_POD_NAME -- bash
    ```

1. Apply the backup

    ```bash
    gzip -d /tmp/backup.sql.gz
    # Be careful: the next lines have potentially danger operations
    psql -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'waldur' AND pid <> pg_backend_pid();"
    psql -d postgres -c 'DROP DATABASE waldur;'
    createdb waldur
    psql -f /tmp/backup.sql
    rm /tmp/backup.sql
    ```
