# Limiting network access to Mastermind APIs

Waldur Helm allows limiting network access to Mastermind API endpoints - i.e. `/api/`, `/api-auth/`, `/admin/` - based on whitelisting the subnets from where access is allowed. To define a list of allowed subnets in CIDR format for the all the API endpoint, please use `ingress.whitelistSourceRange` option in `values.yaml`. Example:

```yaml
...
ingress:
  whitelistSourceRange: '192.168.22.0/24'
...
```

Given this value, only IPs from `192.168.22.0/24` subnet are able to access Waldur Mastermind APIs.

In case you want to limit access to `/api/admin/` endpoint specifically, there is another option called `ingress.whitelistSourceRangeAdmin`:

```yaml
...
ingress:
  whitelistSourceRangeAdmin: '192.168.22.1/32'
...
```

This will limit access to the admin endpoint only for `192.168.22.1` IP. **Note: The `whitelistSourceRangeAdmin` option takes precedence over `whitelistSourceRange`.**

In case of multiple subnets/IPs, comma separated list can be used as a value. E.g.: `192.168.22.1/32,192.168.21.0/24`. This works for both options.
