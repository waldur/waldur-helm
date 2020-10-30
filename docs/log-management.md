## Log management (EFK)
In this Helm Chart, log management is implemented by EFK (Elasticsearch Fluentd Kibana) stack.

**NB**: If you use minikube, enable `ingress` addon to access Kibana web UI. For this, use the following command: 
```
  minikube addons enable ingress
```

### Fluentd configuration
Fluentd instance runs as a sidecar (support container within a main container's pod) for `mastermind-api`, `mastermind-worker` and `mastermind-beat`.

There are next options for Fluentd configuration in `values.yaml` file (`logManagement` prefix):
1) `enabled` - flag for enabling Fluentd. Possible values: `true` for enabling and `false` for disabling.
2) `elasticHost` - Elasticsearch service host: hostname of `elasticsearch-master` service. See [this doc](service-endpoint.md) for details.
3) `elasticPort` - Elasticsearch service port.
4) `elasticProtocol` - communication protocol with Elasticsearch service.
### Elasticsearch configuration
Elasticsearch instance runs as a standalone Helm release.
 
Install Elasticsearch:
1) Create a namespace for Elasticsearch release:
```
  kubectl create namespace elastic
```
2) Add Elastic repo and update repos list
```
  helm repo add elastic https://helm.elastic.co
  helm repo update
```
3) Install Elasticsearch release
```
  helm install elasticsearch elastic/elasticsearch \
  --namespace elastic \
  -f elastic-values.yaml
```

The last command uses `elastic-values.yaml`, where you can configure:
1) `replicas` - number of replicas (`elasticsearch-master` pods).
2) `resources.requests` - requested resources for each replica.
2) `resources.limits` - resources limits for each replica.

### Kibana configuration
Kibana instance runs as another standalone Helm release.

Install Kibana:
```
  helm install kibana elastic/kibana \
  --namespace elastic \
  -f kibana-values.yaml
```

The last command uses `elastic-values.yaml`, where you can configure:
1) `elasticsearchHosts` - `elasticsearch-master` service URL. See [this doc](service-endpoint.md) for details.
2) `ingress` - ingress configuration (enabled by default). 
3) `resources` - same resources configuration as for Elasticreach release.

You can create index pattern, ILM policy and link them together using `kibana-init-script`:
```
  scripts/kibana-init-script
```

### Log viewing
After configuration, you can view logs by opening
```
  http://<kibana-values.ingress.hosts[0]>/
``` 
in your browser. 

This works only if you set `kibana-values.ingress.enabled=true` and add some hostname into `kibana-values.ingress.hosts` list.

You can also use kubernetes proxy instead of ingress. For this:
Bind proxy to a specific port on your local machine:
```
  kubectl proxy --port=8080
```

Access kibana dashboard:
```
  http://localhost:8080/api/v1/namespaces/elastic/services/http:kibana-kibana:http/proxy
```
