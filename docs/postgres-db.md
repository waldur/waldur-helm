# PostgreSQL chart configuration (without HA support)

[bitnami/postgresql chart](https://github.com/bitnami/charts/tree/master/bitnami/postgresql)
is used as a database for Waldur.

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install `postgresql` release:

```bsah
  helm install postgresql bitnami/postgresql --version 9.8.2 -f postgresql-values.yaml
```

**NB**: the value `postgresql.HAEnabled` for waldur release must be `false`.

## Chart configuration

You can change default PostgreSQL config with the following variables in `postgresql-values.yaml`:

1. `postgresqlDatabase` - name of a database.
    **NB**: must match `postgresql.database` value in `waldur/values.yaml`
1. `postgresqlUsername` - name of a database user.
    **NB**: must match `postgresql.username` value in `waldur/values.yaml`
1. `postgresqlPassword` - password of a database user
1. `persistence.size` - size of a database
1. `image.tag` - tag of `PostgreSQL` image.
    Possible tags for default image can be found [here](https://hub.docker.com/r/bitnami/postgresql/tags)
1. `image.registry` - registry of `PostgreSQL` image.

More information related to possible values [here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql#parameters).
