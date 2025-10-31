# PostgreSQL Configuration

## Production vs Demo Deployments

⚠️ **Important:** This document describes PostgreSQL setup for **demo/development environments only**.

**For production deployments**, use the [CloudNativePG Operator](postgres-operator.md) instead of the Bitnami Helm chart. The operator provides:
- Kubernetes-native PostgreSQL cluster management
- Automated failover and high availability
- Built-in backup and Point-in-Time Recovery (PITR)
- Zero-downtime maintenance operations
- Enhanced monitoring and observability
- Production-grade security features

## Demo/Development Installation

For development and demo environments,
[bitnami/postgresql chart](https://github.com/bitnami/charts/tree/master/bitnami/postgresql)
can be used for quick setup.

## Demo Standalone Installation

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install PostgreSQL release for demo/development:

```bash
  helm install postgresql bitnami/postgresql --version 16.0.1 -f postgresql-values.yaml
```

**Note:** 
- The default configuration in `postgresql-values.yaml` uses `bitnamilegacy` Docker images for compatibility
- This setup is **not recommended for production use**

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
    Possible tags for default image can be found [here](https://hub.docker.com/r/bitnamilegacy/postgresql/tags)
6. `image.registry` - registry of `PostgreSQL` image.

More information related to possible values [here](https://github.com/bitnami/charts/tree/master/bitnami/postgresql#parameters).

**Important:** 
- The PostgreSQL configuration uses legacy Bitnami images (`bitnamilegacy/postgresql` and `bitnamilegacy/postgres-exporter`) for demo/development compatibility
- These images are configured in the `postgresql-values.yaml` file
- For production deployments, migrate to the [CloudNativePG Operator](postgres-operator.md)

## Demo Dependency Installation

Waldur Helm chart supports PostgreSQL installation as a dependency.
For this, set `postgresql.enabled` to `true` and update related settings in `postgresql` section in `waldur/values.yaml`

**NB**: the value `postgresqlha.enabled` and `externalDB.enabled` must be `false`.

Prior Waldur installation, update chart dependencies:

```bash
helm dependency update
```

## Readonly user configuration

In order to enable /api/query/ endpoint please make sure that read-only user is configured.

```sql
-- Create a read-only user
CREATE USER readonly WITH PASSWORD '{readonly_password}'

-- Grant read-only access to the database
GRANT CONNECT ON DATABASE '{database_name}' TO '{readonly_username}'

-- Grant read-only access to the schema
GRANT USAGE ON SCHEMA public TO '{readonly_username}'

-- Grant read-only access to existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO '{readonly_username}'

-- Grant read-only access to future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO '{readonly_username}'

-- Revoke access to authtoken_token table
REVOKE SELECT ON authtoken_token FROM '{readonly_username}'
```
