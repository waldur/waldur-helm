# Waldur

Waldur is a platform for creating hybrid cloud solutions. It allows building enterprise-grade systems and providing self-service environment for the end-users.

## Introduction

This chart bootstraps a [Waldur](https://waldur.com/) deployment on a Kubernetes cluster using the [Helm](https://helm.sh) package manager.

## Installing prerequisites

1. Install Kubernetes server, for example, using [minikube](/docs/minikube.md)
2. Install Kubernetes client, ie [kubetcl](/docs/kubectl.md)
3. Install [Helm](/docs/helm.md)

## TLS configuration
Instructions for TLS configuration: [doc](/docs/tls-config.md)

## SAML2 configuration
You can configure SAML2 for Waldur release: [instructions](/docs/saml2.md)

## Installing the Chart

1. Add the stable repository
```
  helm repo add stable https://kubernetes-charts.storage.googleapis.com
```
2. Install Chart dependencies:
```
  helm dep update waldur
```
3. Install zalando postgres operator: [instructions](/docs/pg-operator.md)
4. Install minio (for media): [instructions](/docs/minio.md)
5. Install RabbitMQ for task queue: [instructions](/docs/rabbitmq.md)
5. Install Helm package:
```
  # in 'waldur-helm-poc/'
  helm install waldur waldur
```
**NB** After this command, Waldur release will run in `default` namespace. Please, pay attention in which namespace which release is running.

For instance, you can install Waldur release in `test` namespace in the following way:
1. Create `test` namespace:
```
  kubectl create namespace test
```
2. Install release:
```
  helm install waldur waldur --namespace test
```

## Adding admin user
Open waldur-mastermind-worker shell and execute the following command:

1. Get waldur-mastermind-worker pod name
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
3. Execute command to add admin user
```
  waldur createstaffuser -u user -p password -e admin@example.com
```

## White-labeling
Instructions for while-labeling: [doc](/docs/whitelabeling.md)

## Custom mastermind templates

Instructions for template configuration: [doc](/docs/mastermind-templates.md)

## HPA (horizontal pod autoscaler)
Instructions for HPA configuration: [doc](/docs/hpa.md)

## EFL (Elasticsearch Fluentd Kibana) for log management configuration
Instructions for EFL configuration: [doc](/docs/log-management.md)

## Stress testing
Instructions for stress testing configuration using Locust: [doc](/docs/locust.md)
