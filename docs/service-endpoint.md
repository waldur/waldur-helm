# Service endpoints

For communication inside a cluster, pods use services.
Usually, that needs to define internal endpoints with service URL format.

**NB**: It is important to set up `namespace` part correctly.
If not, requests can come to unexpected service, which will cause errors.

## Endpoint format

Fully qualified endpoint format is:

```bash
http://<service-name>.<namespace>.svc.<cluster>:<service-port>
```

Where

- `<service-name>.<namespace>.svc.<cluster>` - hostname of service
- `<service-port>` - port of service

For example:

- hostname is `elasticsearch-master.elastic.svc.cluster.local`
- service port is `9200`
- final URL is `http://elasticsearch-master.elastic.svc.cluster.local:9200`

If pods run in the same namespace and cluster, it can be simplified to:

```bash
http://<service-name>:<service-port>
```

For example: `http://elasticsearch-master:9200`
