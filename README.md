# Waldur

Waldur is a platform for creating hybrid cloud solutions. It allows building enterprise-grade systems and providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment on a Kubernetes cluster using the [Helm](https://helm.sh) package manager.

## Installing Helm

Check [Helm readme](https://github.com/helm/helm#install).

## Installing the Chart

1. Download this git repo
2. Open values.yaml and change api_url and homeport_url.
3. Open waldur-homeport/config.json and change "apiEndpoint"
4. Open templates/secrets_config.yaml and change DB password and global secret key
5. Create a new catalog. To do this you need a working web server. Consider [Ngrok](https://ngrok.com/) for development.
```
  helm package waldur --version 1.1.133
  mv waldur-*.tgz waldur
  helm repo waldur --url http://<web server address>/<chart directory>/
```
5. Add repo to the Rancher catalog
6. Install Waldur

## Adding admin user

Open waldur-mastermind-worker shell and execute the following command:

```waldur createstaffuser -u user -p password```

## Known problems

1. waldur-mastermind-job which triggers database populating command "waldur migrate" runs too soon. The database is not ready and then first startup fails and only second can finish job.
