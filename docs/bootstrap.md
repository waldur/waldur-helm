# Bootstrap configuration

You can create a bootstrapping script and Helm will run
it right after Waldur release installation.

Example script:

```bash
  #!/bin/bash
  set -e

  echo "[+] Creating staff user"
  waldur createstaffuser -u admin -p admin -e admin@example.com
  echo "[+] Done"

  exit 0
```

This script with all necessary additional files
should be placed in `bootstrap.dir` directory.

Additional configuration variables (`bootstrap` prefix):

1. `enabled` - enable/disable bootstrap
2. `script` - main script file in `bootstrap.dir` folder.
3. `dir` -  directory with all bootstrap files

Moreover, that is better to install release with `--wait` flag:

```bash
  helm install waldur waldur/ --wait --timeout 10m0s
```

This allows running migrations job before a bootstrap one.
more info: [link](https://helm.sh/docs/topics/charts_hooks/),
`Hooks and the Release Lifecycle` section)

**NB**:

* A script, which contains interaction with a db can fail
  due to not all migrations are applied.
  Automatical reruning of the bootstrap job is normal behaviour in such situations.

* Hence, the script should be **idempotent**.
