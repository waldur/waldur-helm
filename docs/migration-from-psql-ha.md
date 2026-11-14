# Migration from Postgresql HA

**The `postgresql-ha` subchart has been removed.** It was frozen upstream at
images that only exist in Bitnami's archived `bitnamilegacy` registry, and no
replacement subchart offers real HA — every credible option is an operator, which
cannot work as a plain Helm dependency.

Migrate to a Postgres operator via `externalDB` — see
[PostgreSQL Operators](postgres-operator.md) and
[External DB Integration](external-db-integration.md). The bundled
[single-node PostgreSQL](postgres-db.md) is a dev/test destination only.

The dump-and-restore steps below still apply; the destination has changed.

Plan:

1. Scale api, beat, worker -> 0

2. Back up the database — with the backup job or the `pg_dump` below

3. Provision the destination database (an operator-managed cluster)

4. Restore the dump into the destination

5. Point the release at the destination (`externalDB.*`), drop the
   `postgresql-ha` values and run `helm upgrade`

6. Validate that login works

7. Drop the old `postgresql-ha` StatefulSet and its PVCs

```bash

# Backup

kubectl exec -it postgresql-ha-waldur-postgresql-0 -- env PGPASSWORD=waldur pg_dump -h 0.0.0.0 -U waldur waldur | gzip -9 > backup.sql.gz

# Backup restoration
# Locally

kubectl cp backup.sql.gz <destination-primary-pod>:/tmp/backup.sql.gz
kubectl exec -it <destination-primary-pod> -- bash

# In the destination pod

gzip -d /tmp/backup.sql.gz
export PGPASSWORD=waldur
psql -U waldur -h 0.0.0.0 -f /tmp/backup.sql
```
