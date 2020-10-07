## PostgreSQL chart configuration (without HA support)
[bitnami/postgresql](https://github.com/bitnami/charts/tree/master/bitnami/postgresql) is used as a pluggable dependency for Waldur Helm chart.
### Chart configuration
You can change default PostgreSQL config with the following variables in `values.yaml` (`postgres` prefix):
1. `enabled` - boolean flag for enabling/disabling postgres chart. **NB:** must be different than `.Values.postgresql-ha.enabled`
2. `postgresqlDatabase` - name of a database
3. `postgresqlUsername` - name of a database user
4. `postgresqlPassword` - password of a database user
5. `persistence.size` - size of a database
6. `image.tag` - tag of `PostgreSQL` image. Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/postgresql/tags)
7. `exisitingSecret` - secret with passwords (if exists)

More information related to possible values [here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql#parameters).
