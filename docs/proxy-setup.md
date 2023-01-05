# Proxy setup for Waldur components

You can setup the proxy environment variables `https_proxy`, `http_proxy` and `no_proxy` for Waldur component containers.
For this, please set values for the `proxy.httpsProxy`, `proxy.httpProxy` and `proxy.noProxy` variables in `waldur/values.yaml` file.

Example:

```yaml
proxy:
  httpsProxy: "https://proxy.example.com/"
  httpProxy: "http://proxy.example.com/"
  noProxy: ".test"
```

**Note**: you can set variables separately, i.e. leave some of them blank:

```bash
proxy:
  httpsProxy: ""
  httpProxy: "http://proxy.example.com/"
  noProxy: ".test"
```

In the previous example, the `https_proxy` env variable won't be present in the containers.
