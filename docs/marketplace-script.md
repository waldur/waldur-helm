# Waldur Marketplace script plugin setup

Available options in `values.yaml`:

- `waldur.marketplace.script.enabled` - enable/disable plugin
- `waldur.marketplace.script.dockerImages` - key-value structure, where key is a programming language
  and value - a corresponding docker image tag
- `waldur.marketplace.script.k8sNamespace` - Kubernetes namespace, where jobs will be executed
- `waldur.marketplace.script.kubeconfigPath` - path to local file with kubeconfig content
- `waldur.marketplace.script.kubeconfig` - kubeconfig file content takes precedence over `.kubeconfigPath` option
- `waldur.marketplace.script.jobTimeout` - timeout for Kubernetes jobs
