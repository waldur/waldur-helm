# RabbitMQ (bundled subchart)

For **demo and development** installs, the chart can bring up its own RabbitMQ.
For **production**, use the [RabbitMQ Cluster Operator](rabbitmq-operator.md).

The subchart is [CloudPirates `rabbitmq`](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/rabbitmq),
which runs the official `docker.io/rabbitmq` image.

## Enabling it

```yaml
rabbitmq:
  enabled: true
  auth:
    username: "waldur"
    password: "waldur"
```

The chart's default values already declare the plugins and ports Waldur needs.

## Plugins and ports

Waldur needs four ports on the broker Service:

| port | purpose | required by |
|---|---|---|
| 5672 | AMQP | Celery broker URL |
| 15672 | management API | `RABBITMQ["MANAGEMENT_PORT"]` |
| 61613 | STOMP | `RABBITMQ["STOMP_PORT"]`, set when `waldur.rabbitmqEvents.stompEnabled` |
| 15674 | web-STOMP | backend of `templates/ingress-rmq-ws.yaml` |

5672 and 15672 are always present. The other two come from the plugins, and this
chart does **not** derive Service ports from plugin names — so `extraPorts` has
to declare them explicitly alongside `additionalPlugins`:

```yaml
rabbitmq:
  additionalPlugins:
    - rabbitmq_stomp
    - rabbitmq_web_stomp
    - rabbitmq_auth_backend_ldap
  extraPorts:
    - name: stomp
      port: 61613
      containerPort: 61613
      targetPort: 61613
    - name: stomp-websocket
      port: 15674
      containerPort: 15674
      targetPort: 15674
```

Drop an entry from either list and the STOMP event stream stops working without
`helm install` failing.

## Credentials

`rabbitmq.auth.username` and `rabbitmq.auth.password` are copied into the
`waldur-secret` Secret by `templates/secrets.yaml`, and the application reads them
from there. When pointing at a broker deployed outside the chart, set
`rabbitmq.enabled: false` plus `rabbitmq.host` and `rabbitmq.secret.*` instead.

## Installing RabbitMQ separately

```bash
helm install rmq oci://registry-1.docker.io/cloudpirates/rabbitmq \
  --version 0.21.19 -f rmq-values.yaml
```

That produces a Service named `rmq-rabbitmq`, the default of `rabbitmq.host`.

## Migrating from the Bitnami subchart

**An existing Bitnami volume cannot be reused, even though the PVC name is the
same.** Bitnami stored mnesia at `/bitnami/rabbitmq/mnesia`; the official image
uses `/var/lib/rabbitmq`. Reattaching the old claim gives RabbitMQ an empty
mnesia directory — it starts clean, with no queues, users or vhosts.

For a dev/test broker that is usually fine: delete the old PVC and let the new
one initialise. For anything with durable state, drain the queues first or export
definitions from the management API and re-import them after the switch.

Values that changed shape: `extraPlugins` (a space-separated string) became
`additionalPlugins` (a list); `extraContainerPorts` and `service.extraPorts`
merged into a single `extraPorts` list; `clustering.forceBoot` has no equivalent.
