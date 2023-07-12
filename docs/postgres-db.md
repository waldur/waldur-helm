# PostgreSQL chart configuration (without HA support)

[bitnami/postgresql chart](https://github.com/bitnami/charts/tree/master/bitnami/postgresql)
is used as a database for Waldur.

## Standalone installation

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install `postgresql` release:

```bash
  helm install postgresql bitnami/postgresql --version 11.9.1 -f postgresql-values.yaml
```

**NB**: the values `postgresql.enabled` and `postgresqlha.enabled` must be `false`.

### Chart configuration

You can change default PostgreSQL config with the following variables in `postgresql-values.yaml`:

1. `auth.database` - name of a database.
    **NB**: must match `postgresql.database` value in `waldur/values.yaml`
2. `auth.username` - name of a database user.
    **NB**: must match `postgresql.username` value in `waldur/values.yaml`
3. `auth.password` - password of a database user
4. `primary.persistence.size` - size of a database
5. `image.tag` - tag of `PostgreSQL` image.
    Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/postgresql/tags)
6. `image.registry` - registry of `PostgreSQL` image.

More information related to possible values [here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql#parameters).

## Dependency installation

Waldur Helm chart supports PostgreSQL installation as a dependency.
For this, set `postgresql.enabled` to `true` and update related settings in `postgresql` section in `waldur/values.yaml`

**NB**: the value `postgresqlha.enabled` and `externalDB.enabled` must be `false`.

Prior Waldur installation, update chart dependencies:

```bash
helm dependency update
```
