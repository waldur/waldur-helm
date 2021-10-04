# Official documentation

Documentation of installation link: [doc](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux)

## Installing kubectl

1. Download and install latest kubectl

```bash
  curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
```

1. Add executable mode for kubectl

```bash
  chmod +x ./kubectl
```

1. Move kubectl binary into your PATH

```bash
  sudo mv ./kubectl /usr/local/bin/kubectl
```

1. Check the version

```bash
  kubectl version --client
```

1. Show running Pods in cluster

```bash
  kubectl get po -A # -->
  # NAMESPACE     NAME                             READY STATUS  RESTARTS AGE
  # kube-system   coredns-66bff467f8-dcfxn         1/1   Running 0        ??m
  # kube-system   coredns-66bff467f8-tdgpn         1/1   Running 0        ??m
  # kube-system   etcd-minikube                    1/1   Running 0        ??m
  # kube-system   kindnet-4j8t6                    1/1   Running 0        ??m
  # kube-system   kube-apiserver-minikube          1/1   Running 0        ??m
  # kube-system   kube-controller-manager-minikube 1/1   Running 0        ??m
  # kube-system   kube-proxy-ft67m                 1/1   Running 0        ??m
  # kube-system   kube-scheduler-minikube          1/1   Running 0        ??m
  # kube-system   storage-provisioner              1/1   Running 0        ??m
```
