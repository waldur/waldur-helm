## PostgreSQL operator configuration
For PostrgreSQL management, [zalando/postgres-operator](https://github.com/zalando/postgres-operator) is used.
### Operator installation and configuration
To use the Helm chart, you need to clone git repository:
```
  git clone git@github.com:zalando/postgres-operator.git
```
After that, install `postgresql-operator` release: 
```
  helm install pg-operator \
    postgres-operator/charts/postgres-operator \
    -f pg-operator-values.yaml
```

Additional config variables can be found [there](https://postgres-operator.readthedocs.io/en/latest/reference/operator_parameters/).

**NB:** setup `configKubernetes` section, especially `configKubernetes.cluster_domain` (by default it is set to local value).

### Cluster configuration
You can change default PostgreSQL config with the following variables in `values.yaml` (`postgres_operator` prefix):
1. `enabled` - boolean flag for enabling/disabling postgres operator. **NB:** must be different than `postgresql.enabled`
2. `version` - a version of available docker image. Check info about versions [here](https://postgres-operator.readthedocs.io/en/latest/administrator/#minor-and-major-version-upgrade)
3. `postgresqlHost` - hostname of the postgres instance. **NB**: this name should have next format: `<team_prefix>-<cluster_name>`. This is important for `postgresql` resource config, which use `<team_prefix>` for cluster identity. More related info [here](https://postgres-operator.readthedocs.io/en/latest/user/#create-a-manifest-for-a-new-postgresql-cluster) (check the last paragraph)
4. `postgresqlDatabase` - name of a database
5. `postgresqlUsername` - name of a database user
6. `replicaCount` - number of replicas for postgres (for HA support, it needs to be greater than 1)
7. `storageClass` - name of a storage class 
8. `loadBalancing` - LB configuration for master and replicas. Check info about load balancers [here](https://postgres-operator.readthedocs.io/en/refactoring-sidecars/administrator/#load-balancers)

    8.1 `enableMaster`- enable LB for master
    
    8.2 `enableReplica`- enable LB for replicas

9. `enableLogicalBackup` - enable backup for database. More related info [here](https://postgres-operator.readthedocs.io/en/latest/administrator/#logical-backups)
