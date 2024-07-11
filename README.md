# Waldur Helm

Waldur is a platform for creating hybrid cloud solutions.
It allows building enterprise-grade systems and
providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment
on a Kubernetes cluster using the [Helm](https://helm.sh) package manager.

## Installing prerequisites

1. Install Kubernetes server, for example, using [minikube](docs/minikube.md)
2. Install Kubernetes client, i.e. [kubectl](docs/kubectl.md)
3. Install [Helm](docs/helm.md)

## Installing the chart

1. Clone [waldur-helm repository](https://github.com/waldur/waldur-helm)

```bash
  git clone https://github.com/waldur/waldur-helm.git
  cd waldur-helm
```

1. Add the stable repository

```bash
  helm repo add stable https://charts.helm.sh/stable
```

1. Setup database:
    3.1 Setup single PostgreSQL DB: [instructions](docs/postgres-db.md) or
    3.2 Setup PostgreSQL HA DB: [instructions](docs/postgres-db-ha.md) or
    3.3 Integrate with external DB: [instructions](docs/external-db-integration.md)

    **NB** Only one of these two options should be used. Otherwise, DB will be unavailable.

2. Install minio (for database backups): [instructions](docs/minio.md)
3. Install RabbitMQ for task queue: [instructions](docs/rabbitmq.md)
4. Install Helm package:

```bash
  helm install waldur waldur
```

**NB** After this command, Waldur release will run in `default` namespace.
Please, pay attention in which namespace which release is running.

For instance, you can install Waldur release
in `test` namespace in the following way:

1. Create `test` namespace:

```bash
  kubectl create namespace test
```

1. Install release:

```bash
  helm install waldur waldur --namespace test
```

However, postgresql release and waldur should be installed
in the same namespace in order to share a common secret with DB credentials.

## Adding admin user

Open waldur-mastermind-worker shell and execute the following command:

1. Get waldur-mastermind-worker pod name

```bash
  # Example:
  kubectl get pods -A | grep waldur-mastermind-worker # -->
  # default waldur-mastermind-worker-6d98cd98bd-wps8n 1/1 Running 0 9m9s
```

1. Connect to pod via shell

```bash
  # Example:
  kubectl exec -it deployment/waldur-mastermind-worker -- /bin/bash
```

1. Execute command to add admin user

```bash
  waldur createstaffuser -u user -p password -e admin@example.com
```

## Waldur Helm chart release upgrading

Delete init-whitelabeling job (if exists):

```bash
  kubectl delete job waldur-mastermind-init-whitelabeling-job || true
```

Delete load features job (if exists):

```bash
  kubectl delete job load-features-job || true
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

## Private registry setup

A user can use private registry for Docker images.
For this, the corresponding credentials should be registered in a secret,
name of which should be placed in `.Values.imagePullSecrets`.
A secret can be created trough [CLI](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/#create-a-secret-by-providing-credentials-on-the-command-line).

## Configuration docs

Configuration documentation: [index](docs/index.md)
