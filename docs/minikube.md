## Official documentation
Documentation of installation link: [doc](https://minikube.sigs.k8s.io/docs/start/linux/)
## Installing minikube
1. Download and install minikube
- For Debial/Ubuntu:
```
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_1.9.1-0_amd64.deb \
  && sudo dpkg -i minikube_1.9.1-0_amd64.deb
```
- For Fedora/Red Hat
```
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-1.9.1-0.x86_64.rpm \ 
  && sudo rpm -ivh minikube-1.9.1-0.x86_64.rpm
```
- Others (direct installation)
```
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && sudo install minikube-linux-amd64 /usr/local/bin/minikube
```
2. Set docker as a default driver
```
  minikube config set driver docker
  minikube delete # delete previous profile
  minikube config get driver # --> docker 
```
3. Start local kubernetes cluster
```
  minikube start
  minikube status # -->
  # m01
  # host: Running
  # kubelet: Running
  # apiserver: Running
  # kubeconfig: Configured
```
