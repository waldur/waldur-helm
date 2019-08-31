# Waldur

Waldur is a platform for creating hybrid cloud solutions. It allows building enterprise-grade systems and providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment on a [Rancher](https://rancher.com/) cluster using the [Helm](https://helm.sh) package manager.

## Installing the Chart

1. Download this git repo
2. Open values.yaml and change api_url and homeport_url.
3. Open waldur-homeport/config.json and change "apiEndpoint"
4. Open templates/secrets_config.yaml and change DB password and global secret key
5. Create new catalog. To do this you need working web server. Download Waldur helm to the web catalog and create tar and index with following commands

helm package waldur --version 1.1.133
mv nginx-*.tgz waldur
helm repo waldur nginx --url http://<web server address>/>chart directory>

5. Add repo to the Rancher catalog
6. Install Waldur

## Add admin user

Open waldur-mastermind-worker shell and execute following command

waldur createstaffuser -u user -p password

## Know problems

1. waldur-mastermind-job which triggers database populating command "waldur migrate" runs too soon. The database is not ready and then first startup fails and only second can finish job.
