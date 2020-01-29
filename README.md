# Waldur

Waldur is a platform for creating hybrid cloud solutions. It allows building enterprise-grade systems and providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment on a Kubernetes cluster using the [Helm](https://helm.sh) package manager.

## Installing prerequisites

1. Install Kubernetes server, for example, using [minikube](https://minikube.sigs.k8s.io/docs/start/linux/)
2. Install Kubernetes client, ie [kubetcl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux)
3. Install [Helm](https://helm.sh/docs/intro/install/#from-script)
4. Install [ChartMuseum](https://chartmuseum.com/docs/#installation)
5. Start ChartMuseum with [local storage](https://chartmuseum.com/docs/#using-with-local-filesystem-storage)

## Installing the Chart

1. Download this git repo
2. Open values.yaml and update apiUrl and homeportUrl.
3. Open waldur-homeport/config.json and change "apiEndpoint"
4. Open templates/secrets_config.yaml and change DB password and global secret key
5. Create a helm package.
```
  helm package waldur --version 3.9.5
```
6. Upload Helm package to the local repository:
```
  curl --data-binary "@waldur-3.9.5.tgz" http://localhost:8080/api/charts
```
7. Install Helm package from local repository:
```
  helm install chartmuseum/waldur --generate-name
```
8. Expose helm repository on public URL (using e.g [Ngrok](https://ngrok.com/)):
```
  ngrok http http://localhost:8879/
```

## Adding admin user

Open waldur-mastermind-worker shell and execute the following command:

```waldur createstaffuser -u user -p password```

## Known problems

1. waldur-mastermind-job which triggers database populating command "waldur migrate" runs too soon. The database is not ready and then first startup fails and only second can finish job.
