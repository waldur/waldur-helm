# Waldur

Waldur is a platform for creating hybrid cloud solutions. It allows building enterprise-grade systems and providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment on a Kubernetes cluster using the [Helm](https://helm.sh) package manager.

## Installing Helm

Check [Helm readme](https://github.com/helm/helm#install).

Run ```helm init``` before proceeding.

## Installing the Chart

1. Download this git repo
2. Open values.yaml and update apiUrl and homeportUrl.
3. Open waldur-homeport/config.json and change "apiEndpoint"
4. Open templates/secrets_config.yaml and change DB password and global secret key
5. Create a helm package (also deploys it to a local repository) Consider for development.
```
  helm package waldur --version 3.9.5
```
5. Expose helm repository on public URL (using e.g [Ngrok](https://ngrok.com/)):
```
  helm serve
  ngrok http http://localhost:8879/
```
6. Install Waldur

## Adding admin user

Open waldur-mastermind-worker shell and execute the following command:

```waldur createstaffuser -u user -p password```

## Known problems

1. waldur-mastermind-job which triggers database populating command "waldur migrate" runs too soon. The database is not ready and then first startup fails and only second can finish job.
