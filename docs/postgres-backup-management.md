## PostgreSQL backup configuration
There are three jobs for backups managemet:
- CronJob for backups creation (running by a schedule `postgresBackup.schedule`)
- Simple Job for backups creation (running before Waldur Helm release upgrade)
- CronJob for backups rotation (running by a schedule `postgresBackup.rotationSchedule`)

Backup configuration values (`postgresBackup` prefix):
- `enabled` - boolean flag for enabling/disabling backups 
- `schedule` - cron-like schedule for backups
- `rotationSchedule` - cron-like schedule for backups rotation
- `retentionDays` - number of days for backups retetion
- `minNumber` - minnimum number of backups to store (takes presedence over `retentionDays` variable)
- `image` - image containing `potgres` and `minio` (client) binaries ([opennode/postgres-minio](https://hub.docker.com/r/opennode/postgres-minio) by default)

## Backups restoration
To restore backups you need to shell into `waldur-db-restore` pod and execute the following script:
```bash
  db-backup-minio-auth
  mc cp pg/$MINIO_BUCKET/backups/postgres/<selected backup> backup.sql.gz
  gzip -d backup.sql.gz
  cat backup.sql | psql -U $POSTGRESQL_USER -h $POSTGRESQL_HOST -d $POSTGRESQL_NAME
  rm backup.sql
```
