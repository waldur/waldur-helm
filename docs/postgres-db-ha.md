# PostgreSQL HA Configuration

## Production vs Demo Deployments

⚠️ **Important:** This document describes PostgreSQL HA setup for **demo/development environments only**.

**For production deployments**, use the [CloudNativePG Operator](postgres-operator.md) instead of the Bitnami HA chart. The operator provides:
- True Kubernetes-native high availability
- Automated failover with zero data loss
- Built-in streaming replication
- Comprehensive backup and recovery
- Superior monitoring and observability
- Production-grade security and networking

## Demo/Development HA Installation

For development and demo environments requiring basic HA,
[bitnami/postgresql-ha](https://github.com/bitnami/charts/tree/master/bitnami/postgresql-ha)
can be used for quick setup.

## Demo HA Installation

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install PostgreSQL HA release for demo/development:

```bash
  helm install postgresql-ha bitnami/postgresql-ha \
    -f postgresql-ha-values.yaml --version 14.2.34
```

**Note:** 
- The default configuration in `postgresql-ha-values.yaml` uses `bitnamilegacy` Docker images for compatibility
- This setup provides basic HA but is **not recommended for production use**

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
    Possible tags for default image can be found [here](https://hub.docker.com/r/bitnamilegacy/pgpool/tags)
8. `postgresql.image.tag` - tag of `PostgreSQL` image.
     Possible tags for default image can be found [here](https://hub.docker.com/r/bitnamilegacy/postgresql-repmgr/tags/)

More information related to possible values
[here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql-ha#parameters).

**Important:** 
- The PostgreSQL HA configuration uses legacy Bitnami images (`bitnamilegacy/postgresql-repmgr` and `bitnamilegacy/pgpool`) for demo/development compatibility
- These images are configured in the `postgresql-ha-values.yaml` file
- For production deployments, migrate to the [CloudNativePG Operator](postgres-operator.md) which provides superior HA capabilities

## Demo HA Dependency Installation

Waldur Helm chart supports PostgreSQL HA installation as a dependency.
For this, set `postgresqlha.enabled` to `true` and update related settings in `postgresqlha` section in `waldur/values.yaml`

**NB**: the value `postgresql.enabled` and `externalDB.enabled` must be `false`.

Prior Waldur installation, update chart dependencies:

```bash
helm dependency update
```
