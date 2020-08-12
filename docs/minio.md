## Min.io configuration
Min.io storage is used for media data.

Add `minio` chart repo:
```
  helm repo add minio https://helm.min.io/
```
Install `minio` release run:
```
  helm install minio minio/minio -f minio-values.yaml
```
You can change `minio` config with next vars (in `minio.values` file):
1. `accessKey` - access key id for storage
2. `secretKey` - secret key itself
3. `serviceAccount.name` - name of the service account for min.io
4. `persistence.enabled` - persistence enabling flag
5. `persistence.size` - size of storage per each pod 
6. `ingress` - ingress settings
7. `defaultBucket` - default bucket settings

For more configuration values follow [this link](https://github.com/helm/charts/tree/master/stable/minio#configuration).

In Waldur Helm `values.yaml` you need to setup:
1. `minio.accessKey` - should be same as `accessKey` in `minio.values.yaml`
2. `minio.secretKey` - should be same as `secretKey` in `minio.values.yaml`
3. `minio.bucketName` - should be same as `defaultBucket.name` in `minio.values.yaml`
4. `minio.endpoint` - access URL to `minio` storage (`minio` service host and port). See [this doc](service-endpoint.md) for details.
