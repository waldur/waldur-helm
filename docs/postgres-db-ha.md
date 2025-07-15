# PostgreSQL HA chart configuration

[bitnami/postgresql-ha](https://github.com/bitnami/charts/tree/master/bitnami/postgresql-ha)
is used as a highly available database for Waldur.

## Standalone installation

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install `postgresql-ha` release:

```bash
  helm install postgresql-ha bitnami/postgresql-ha \
    -f postgresql-ha-values.yaml --version 14.2.34
```

**NB**: the value `postgresqlha.enabled` for waldur release must be `true`.

### Chart configuration

You can change default PostgreSQL config with
the following variables in `values.yaml` (`postgresql-ha-values.yaml` file):

1. `postgresql.database` - name of a database.
    **NB**: must match `postgresqlha.postgresql.database` value in `waldur/values.yaml`
2. `postgresql.username` - name of a database user.
    **NB**: must match `postgresqlha.postgresql.username` value in `waldur/values.yaml`
3. `postgresql.password` - password of a database user
4. `postgresql.replicaCount` - number of db replicas
5. `postgresql.repmgrPassword` - password of `repmgr` user
6. `persistence.size` - size of a database (for each replica)
7. `pgpool.image.tag` - tag of `Pgpool` image.
    Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/pgpool/tags)
8. `postgresql.image.tag` - tag of `PostgreSQL` image.
     Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/postgresql-repmgr/tags/)

More information related to possible values
[here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql-ha#parameters).

## Dependency installation

Waldur Helm chart supports PostgreSQL HA installation as a dependency.
For this, set `postgresqlha.enabled` to `true` and update related settings in `postgresqlha` section in `waldur/values.yaml`

**NB**: the value `postgresql.enabled` and `externalDB.enabled` must be `false`.

Prior Waldur installation, update chart dependencies:

```bash
helm dependency update
```
