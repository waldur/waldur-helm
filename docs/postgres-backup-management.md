# PostgreSQL backup configuration

There are the following jobs for backups management:

- CronJob for backups creation (running by a schedule `postgresBackup.schedule`)

- CronJob for backups rotation (running by a schedule `postgresBackup.rotationSchedule`)

Backup configuration values (`postgresBackup` prefix):

- `enabled` - boolean flag for enabling/disabling backups

- `schedule` - cron-like schedule for backups

- `rotationSchedule` - cron-like schedule for backups rotation

- `retentionDays` - number of days for backups retetion

- `maxNumber` - maximum number of backups to store
  (takes presedence over `retentionDays` variable)

- `image` - Docker image containing `potgres` and `minio` (client) binaries
  ([opennode/postgres-minio](https://hub.docker.com/r/opennode/postgres-minio)
  by default)

## Backups restoration

To restore backups you need to shell into `waldur-db-restore`
pod and execute the following script:

```bash
  db-backup-minio-auth
  mc cp pg/$MINIO_BUCKET/backups/postgres/<selected backup> backup.sql.gz
  gzip -d backup.sql.gz
  cat backup.sql | psql -U $POSTGRESQL_USER -h $POSTGRESQL_HOST -d $POSTGRESQL_NAME
  rm backup.sql
```
