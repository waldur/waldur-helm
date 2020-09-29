## PostgreSQL chart configuration
[bitnami/postgresql](https://github.com/bitnami/charts/tree/master/bitnami/postgresql) is used as a pluggable dependency for Waldur Helm chart.
### Chart configuration
You can change default PostgreSQL config with the following variables in `values.yaml` (`postgres` prefix):
1. `enabled` - boolean flag for enabling/disabling postgres chart. **NB:** must be different than `postgresql_operator.enabled`
2. `postgresqlDatabase` - name of a database
3. `postgresqlUsername` - name of a database user
4. `postgresqlPassword` - database user's password
5. `persistence.size` - size of database
6. `image.tag` - version of postgres
7. `exisitingSecret` - secret with passwords (if exists)

More information related to possible values [here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql#parameters).
