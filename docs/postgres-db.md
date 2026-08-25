# PostgreSQL (bundled subchart)

For **demo and development** installs, the chart can bring up its own PostgreSQL.
For **production**, use an operator instead — see
[PostgreSQL Operators](postgres-operator.md) and
[External DB Integration](external-db-integration.md).

The subchart is [CloudPirates `postgres`](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/postgres),
which runs the official `docker.io/postgres` image.

## Enabling it

```yaml
postgresql:
  enabled: true
  auth:
    username: "waldur"
    password: "waldur"
    database: "waldur"
  persistence:
    enabled: true
    size: "10Gi"
```

Then `helm dependency update waldur/ && helm install waldur waldur/ -f values.yaml`.
Nothing else is needed: the chart derives the database host and credentials from
the subchart's own Service and Secret.

`externalDB.enabled` takes precedence over this, so leave it `false` when using
the bundled database.

## PostgreSQL version

`waldur/values.yaml` pins `postgresql.image.tag` to a 17.x release because
`templates/_helpers.tpl` hardcodes `waldur.postgresql.version: 17`, which selects
the client image used by the initdb and backup containers. **Move both together** —
`pg_dump` and `psql` refuse to talk to a server newer than themselves.

## Installing PostgreSQL separately

To run PostgreSQL as its own release rather than as a subchart, use
`postgresql-values.yaml` from the repository root:

```bash
helm install postgresql oci://registry-1.docker.io/cloudpirates/postgres \
  --version 0.20.1 -f postgresql-values.yaml
```

Its `nameOverride: "waldur"` produces a Service and Secret named
`postgresql-waldur`, which is what the chart falls back to when neither
`externalDB.enabled` nor `postgresql.enabled` is set.

## Migrating from the Bitnami subchart

Earlier releases used the Bitnami `postgresql` and `postgresql-ha` subcharts.
Both are gone: Bitnami moved its images to a frozen `bitnamilegacy` archive, and
the chart's own image references no longer resolve.

**An existing Bitnami volume cannot be reused, even though the PVC name is the
same.** Bitnami stored data at `/bitnami/postgresql`; the official image uses
`/var/lib/postgresql/data`. Reattaching the old claim gives PostgreSQL a
directory it does not recognise, and it will refuse to initialise into it.

Migrate with a dump and restore:

```bash
kubectl exec -it <old-postgres-pod> -- pg_dump -U waldur waldur | gzip > waldur.sql.gz
# switch the values over, delete the old PVC, install
gunzip -c waldur.sql.gz | kubectl exec -i <new-postgres-pod> -- psql -U waldur waldur
```

`postgresql-ha` has no replacement subchart. It was frozen upstream, and every
credible HA option is an operator that cannot work as a plain Helm dependency —
use [PostgreSQL Operators](postgres-operator.md) via `externalDB`.

One behavioural note: `postgresql-ha` used pgpool, and the chart forced
`DISABLE_SERVER_SIDE_CURSORS` on because transaction pooling breaks Django's
named cursors. Nothing forces it now. If you front the database with any
transaction-pooling proxy — PgBouncer under CloudNativePG or Zalando's connection
pooler — set `externalDB.disableServerSideCursors: "true"` yourself.
