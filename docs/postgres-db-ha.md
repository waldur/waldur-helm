## PostgreSQL HA chart configuration 
[bitnami/postgresql-ha](https://github.com/bitnami/charts/tree/master/bitnami/postgresql-ha) is used as a pluggable dependency for Waldur Helm chart.
### Chart configuration
You can change default PostgreSQL config with the following variables in `values.yaml` (`postgres-ha` prefix):
1. `enabled` - boolean flag for enabling/disabling `postgres-ha` chart. **NB:** must be different than `.Values.postgresql.enabled`
2. `postgresql.database` - name of a database
3. `postgresql.username` - name of a database user
4. `postgresql.password` - password of a database user
5. `postgresql.exisitingSecret` - secret with passwords (if exists)
6. `postgresql.replicaCount` - number of db replicas
7. `postgresql.syncReplication` - enable/disable synchronous replication
8. `postgresql.repmgrUsername` - username of `repmgr` user
9. `postgresql.repmgrPassword` - password of `repmgr` user
10. `persistence.size` - size of a database (for each replica)
11. `pgpoolImage.tag` - tag of `Pgpool` iamge. Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/pgpool/tags)
11. `postgresqlImage.tag` - tag of `PostgreSQL` image. Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/postgresql-repmgr/tags/)

More information related to possible values [here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql-ha#parameters).
