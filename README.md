# Waldur Helm

Waldur is a platform for creating hybrid cloud solutions. It allows building enterprise-grade systems and
providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment on a Kubernetes cluster using the [Helm](https://helm.sh) package manager.

## Installing prerequisites

1. Install Kubernetes server, for example, using [minikube](/docs/minikube.md)
2. Install Kubernetes client, i.e. [kubectl](/docs/kubectl.md)
3. Install [Helm](/docs/helm.md)

## Installing the Chart

1. Add the stable repository
```
  helm repo add stable https://charts.helm.sh/stable
```
2. Install Chart dependencies:
```
  helm dep update waldur
```
3. Setup database:

    3.1 Setup single PostgreSQL DB: [instructions](/docs/postgres-db.md), or

    3.2 Setup PostgreSQL HA DB: [instructions](/docs/postgres-db-ha.md)

    **NB** Only one of these two options should be used. Otherwise, DB will be unavailable.
4. Install minio (for database backups): [instructions](/docs/minio.md)
5. Install RabbitMQ for task queue: [instructions](/docs/rabbitmq.md)
5. Install Helm package:
```
  # in 'waldur-helm/'
  helm install waldur waldur
```
**NB** After this command, Waldur release will run in `default` namespace. Please, pay attention in which namespace which release is running.

## Access waldur-mastermind-worker shell 
In order to add admin users, add categories, and interact with Waldur, we need to get shell access to the waldur-mastermind-worker. 

1. Get waldur-mastermind-worker pod name by running the following kubectl command:
```
  # Example:
  kubectl get pods -A | grep waldur-mastermind-worker # -->
  # default       waldur-mastermind-worker-6d98cd98bd-wps8n   1/1     Running     0          9m9s
```
2. Connect to pod via shell
```
  # Example:
  kubectl exec -it waldur-mastermind-worker-6d98cd98bd-wps8n -- /bin/bash
```
3. You now have shell access. See the underneath examples for creating admin accounts and importing categories to Waldur marketplace. 

## Adding admin user
Open waldur-mastermind-worker shell as described above, and execute the following command:

1. Execute command to add admin user
```
  waldur createstaffuser -u user -p password -e admin@example.com
```

## Importing categories to marketplace
Open waldur-mastermind-worker shell as described above, and execute the following command:

1. Execute the command followed by each category to be imported, seperated by spacing.
```
  waldur load_categories 
  
  # Example: 
  waldur load_categories backup consultancy collocation cms db email hpc lumi licenses vm vpc network operations security storage measurement_devices
  
```

2. In order to utilise Waldur with OpenStack, we need to define the default categories for VM, VPC and Storage services. Login to the Waldur API by accessing your selected API URL, followed by /admin. Sign in with your admin credentials. 

3. Select Marketplace -> Marketplace -> Categories. From here, select the category to be defined, and select the default category option. Save your changes and repeat for other categories. Waldur Marketplace is now ready for integration. 


## Waldur Helm chart release upgrading
Delete initdb job (if exitsts):
```bash
  kubectl delete job waldur-mastermind-initdb-job || true
```

Upgrade Waldur dependencies and release:
```bash
  helm dep update waldur/
  helm upgrade waldur waldur/
```

Restart deployments to apply configmaps changes:

```bash
  kubectl rollout restart deployment waldur-mastermind-beat
  kubectl rollout restart deployment waldur-mastermind-api
  kubectl rollout restart deployment waldur-mastermind-worker
  kubectl rollout restart deployment waldur-homeport
```

## Configuration docs
Configuration documentation: [index](docs/index.md)
