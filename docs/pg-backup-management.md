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
- `imageTag` - tag of [opennode/postgres-minio](https://hub.docker.com/r/opennode/postgres-minio) image
