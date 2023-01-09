# Host aliasing

You can specify additional hosts for Waldur containers in the same manner as the `/etc/hosts` file using [host aliasing](https://kubernetes.io/docs/tasks/network/customize-hosts-file-for-pods/). To create aliases, a user needs to modify the `hostAliases` variable in `waldur/values.yaml` file. Example:

```yaml
hostAliases:
  - ip: "1.2.3.4"
    hostnames:
      - "my.host.example.com"
```

This will add a record for `my.host.example.com` to the `/etc/hosts` file of all the Waldur containers
