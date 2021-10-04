# Min.io configuration

Min.io storage is used as a database backup storage.

Add `bitnami` repo to helm:

```bash
  helm repo add bitnami https://charts.bitnami.com/bitnami
```

Install `minio` release:

```bash
  helm install minio bitnami/minio -f minio-values.yaml
```

You can change `minio` config with next vars (in `minio.values` file):

1. `accessKey.password` - access key id for storage
1. `secretKey.password` - secret key itself
1. `serviceAccount.name` - name of the service account for MinIO
1. `persistence.enabled` - persistence enabling flag
1. `persistence.size` - size of storage per each pod
1. `ingress` - ingress settings
1. `defaultBuckets` - default buckets created after
    release installation (comma-separated list of strings)

For more configuration values follow [this link](https://github.com/bitnami/charts/tree/master/bitnami/minio#parameters).

In Waldur Helm `values.yaml` you need to setup:

1. `minio.accessKey` - should be same as `accessKey` in `minio.values.yaml`
1. `minio.secretKey` - should be same as `secretKey` in `minio.values.yaml`
1. `minio.bucketName` - should be same as a value from `defaultBuckets` list in `minio-values.yaml`
1. `minio.endpoint` - access URL to `minio` storage
    (`minio` service host and port). See [this doc](service-endpoint.md) for details.
