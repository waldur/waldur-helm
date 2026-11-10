# Demo presets

Demo presets are ready-made demo data sets shipped with Waldur. With demo presets
enabled, staff can list, preview and load them through the API and the portal.

**Loading a preset deletes every organization, project, offering, user and token
in the database.** Enable this on demo deployments only.

```yaml
waldur:
  demoPresets:
    enabled: true
    # Preset names to offer; leave empty to offer every preset.
    allowed:
      - hpc_ai_platform
      - call_management
```

The chart sets `WALDUR_DEMO_PRESETS_ENABLED` and `WALDUR_DEMO_PRESETS_ALLOWED` on the
API and the Celery worker. These settings come from the deployment only; they cannot
be changed from the portal. With `enabled: false` (the default), every demo preset
endpoint answers 404. The `waldur demo_presets` command in a pod is not affected.

## Deployment presets, overlay and staff password

A deployment can add presets of its own, keep what it needs across every load,
and stop the published staff passwords from working:

```yaml
waldur:
  demoPresets:
    enabled: true
    # A ConfigMap with one <name>.json key per preset, mounted at
    # /etc/waldur/presets. A preset named like a built-in one replaces it.
    presetsConfigMap: site-presets
    # Imported after every load that cleans up first; never offered itself.
    overlay: site-infra
    # The presets' staff users get this password instead of the published one.
    staffPassword:
      existingSecret: demo-staff
      key: password
```

```bash
kubectl create configmap site-presets --from-file=presets/
kubectl create secret generic demo-staff --from-literal=password='...'
```

These three settings are set on the API and the worker whether or not `enabled`
is on, because the `waldur demo_presets` command in a pod uses them too. A
ConfigMap holds at most 1 MiB, which bounds the size of the presets it carries.

The overlay holds what the deployment needs whatever the demo: offerings backed
by its own services, the users and API tokens of its agents, the features it
turns on. A load with `--no-cleanup` does not import it, and a load whose
overlay is missing fails before anything is deleted. To keep an agent's token
from expiring, give its user `"token_lifetime": null` in the overlay.
