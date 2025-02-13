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

1. Add the Waldur Helm repository

    ```bash
      helm repo add waldur-charts https://waldur.github.io/waldur-helm/
    ```

2. Install dependencies or enable them in Helm values

   2.1. Quick setup:

    In `values.yaml` set:
      - `postgresql.enabled` to `true`
      - `rabbitmq.enabled` to `true`

    One-liner:

    ```bash
    helm install my-waldur --set postgresql.enabled=true --set rabbitmq.enabled=true waldur-charts/waldur
    ```

   2.2. Advanced setup of dependencies
      Setup databaseusing one of:
      - Simple PostgreSQL DB: [instructions](docs/postgres-db.md) or
      - PostgreSQL HA DB: [instructions](docs/postgres-db-ha.md) or
      - Integrate with external DB: [instructions](docs/external-db-integration.md)

      Install MinIO (for database backups): [instructions](docs/minio.md)

      Install RabbitMQ for task queue: [instructions](docs/rabbitmq.md)

3. Install the Helm chart

    ```bash
      helm install my-waldur waldur-charts/waldur -f path/to/values.yml
    ```

**NB** After this command, Waldur release will run in `default` namespace.
Please, pay attention in which namespace which release is running.

For instance, you can install Waldur release
in `test` namespace in the following way:

1. Create `test` namespace:

    ```bash
      kubectl create namespace test
    ```

2. Install release:

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

2. Connect to pod via shell

    ```bash
      # Example:
      kubectl exec -it deployment/waldur-mastermind-worker -- /bin/bash
    ```

3. Execute command to add admin user

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
