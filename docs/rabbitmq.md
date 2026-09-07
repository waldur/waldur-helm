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

## IPv6-only and dual-stack clusters

The bundled broker works on an IPv6-only cluster out of the box; the chart's
default values carry the wiring and no operator configuration is needed. Two
separate parts of RabbitMQ default to IPv4 and both are redirected:

| part | what defaults to IPv4 | how the chart fixes it |
|---|---|---|
| Erlang name resolution | epmd resolves the node's own hostname through `inet`, which asks for A records only | an inetrc with `{inet6, true}` plus `-proto_dist inet6_tcp`, applied from a `rabbitmq-env.conf` that tests `/proc/net/if_inet6` at container start |
| Cowboy HTTP listeners | the management API (15672) and web-STOMP (15674) bind `0.0.0.0` | `management.tcp.ip = ::` and `web_stomp.tcp.ip = ::` in `rabbitmq.config.extraConfiguration` |

Without the first, the broker aborts at boot even though the AAAA record
resolves:

```text
{epmd_error,"<pod>.<svc>.<ns>.svc.cluster.local",nxdomain}
```

The CLI half of it (`CTL_ERL_ARGS`) is not optional. Both the liveness and the
readiness probe run `rabbitmq-diagnostics -q check_running`, so without it the
broker boots but the pod never becomes ready and every `rabbitmqctl` call hangs
until it times out.

Without the second, the broker runs and AMQP works, but the management API and
the realtime web-STOMP stream behind `templates/ingress-rmq-ws.yaml` are
unreachable. Note that `rabbitmq-diagnostics listeners` reports these two as
`[::]` whether or not they are — `/proc/net/tcp` and `/proc/net/tcp6` inside the
pod are the only reliable check:

```bash
kubectl exec <broker-pod> -- bash -c \
  'tail -n +2 /proc/net/tcp | awk "\$4==\"0A\"{print \$2}"'
```

Binding `[::]` is correct on IPv4-only, IPv6-only and dual-stack clusters alike:
with the Linux default `net.ipv6.bindv6only=0` the same socket also accepts IPv4
connections as v4-mapped. A host whose kernel has IPv6 compiled out or disabled
at boot is the one case that needs an override — empty
`rabbitmq.config.extraConfiguration`; the Erlang half already no-ops there.

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
