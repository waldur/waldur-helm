# External DB integration

Waldur Helm can use an external PostgreSQL deployed within the same Kubernetes cluster.

For this, you need to set the following variables in `values.yaml`:

1. `externalDB.enabled` - toggler for integration; requires `postgresql.enabled` and `postgresqlha.enabled` to be `false`
2. `externalDB.flavor` - a type of the DB management system; currently only `zalando` ([Zalando operator](https://postgres-operator.readthedocs.io/en/latest/)) is supported
3. `externalDB.secretName` - name of the secret with PostgreSQL credentials for Waldur user; should include `username` and `password` keys
4. `externalDB.serviceName` - name of the service linked to PostgreSQL master
