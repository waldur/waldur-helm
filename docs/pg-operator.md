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
You can change default PostgreSQL config with the following variables in `values.yaml` (`postgres` prefix):
1. `version` - a version of available docker image. Check info about versions [here](https://postgres-operator.readthedocs.io/en/latest/administrator/#minor-and-major-version-upgrade)
2. `postgresqlHost` - hostname of the postgres instance. **NB**: this name should have next format: `<team_prefix>-<cluster_name>`. This is important for `postgresql` resource config, which use `<team_prefix>` for cluster identity. More related info [here](https://postgres-operator.readthedocs.io/en/latest/user/#create-a-manifest-for-a-new-postgresql-cluster) (check the last paragraph)
3. `postgresqlDatabase` - name of a database
4. `postgresqlUsername` - name of a database user
5. `replicaCount` - number of replicas for postgres (for HA support, it needs to be greater than 1)
6. `storageClass` - name of a storage class 
7. `loadBalancing` - LB configuration for master and replicas. Check info about load balancers [here](https://postgres-operator.readthedocs.io/en/refactoring-sidecars/administrator/#load-balancers)

    7.1 `enableMaster`- enable LB for master
    
    7.2 `enableReplica`- enable LB for replicas

8. `enableLogicalBackup` - enable backup for database. More related info [here](https://postgres-operator.readthedocs.io/en/latest/administrator/#logical-backups)
