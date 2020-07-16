## Kubedb configuration
1. Install kubedb operator:
```
helm install kubedb-operator appscode/kubedb \
  --version v0.13.0-rc.0 \
  --set apiserver.enableValidatingWebhook=false \
  --set apiserver.enableMutatingWebhook=false
```
2. Wait for operator getting ready (~10 sec)

3. Install kubedb catalog 
```
helm install kubedb-catalog appscode/kubedb-catalog \
  --version v0.13.0-rc.0
```

### PostgreSQL configuration
You can change default PostgreSQL config with next vars in `values.yaml` (`postgres` prefix):
1. `version` - a version of available docker image. List available versions: ```kubectl get postgresversions```
2. `postgresqlHost` - hostname of the postgres instance
3. `postgresqlPort` - port of the postgres instance
4. `postgresqlDatabase` - name of a database
5. `postgresqlUsername` - name of a database user
6. `postgresqlPassword` - password for the user
7. `replicaCount` - number of replicas for postgres (for HA support, it needs to be greater than 1)
8. `storageClassName` - name of a storage class 
9.  `size` - storage size request
