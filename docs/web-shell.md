# Web shell (development only)

Staff can open `waldur shell` in a browser tab from the homeport user menu.
A separate `waldur-mastermind-web-shell` Deployment serves the page and runs
the shell; the API hands staff single-use links to it.

This is for development and demo deployments. The chart refuses to render
the web shell unless `waldur.debug` is true, and the server itself refuses to
start without DEBUG. `waldur.debug` also switches Django's debug mode on.

## Enabling

```yaml
waldur:
  debug: true
  webShell:
    enabled: true
    # Optional. Defaults to <apiScheme>://<apiHostname>/webshell/
    url: ""
```

The chart then:

- runs one `waldur web_shell` pod and a `waldur-mastermind-web-shell` Service;
- routes `/webshell` on the API host to it, through an Ingress or an
  HTTPRoute, behind the same IP allowlist as the Django admin
  (`ingress.whitelistSourceRangeAdmin`, falling back to
  `ingress.whitelistSourceRange`);
- sets `WALDUR_WEB_SHELL_ENABLED` and `WALDUR_WEB_SHELL_URL` on the API, so it
  can issue links, and adds a NetworkPolicy when `networkPolicy.enabled` is set.

With `localApiHostname` set, the routes serve `/webshell` on that host and the
chart passes it to the web shell as an extra allowed Host. Browsers still open
the public URL, and their Origin is checked against it.

The web shell pod mounts only the settings files. SSH keys and the script
kubeconfig are deliberately not mounted into a pod that runs an interactive
shell.

## Access and limits

- Only staff users see the menu entry, and every link works once and expires
  after 60 seconds.
- Logging out of Waldur, losing staff status or being deactivated closes an
  open shell within 30 seconds.
- One shell per user; idle shells close after 15 minutes.
- The page header shows the site, portal, host and database the shell is
  connected to.
