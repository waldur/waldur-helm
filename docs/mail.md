# Outgoing email

The chart configures Waldur's SMTP transport and sender addresses through the
`waldur.mail.*` values. They are rendered into the `override.conf.py` file
mounted by the API, worker and beat pods.

For the settings themselves — what each one does, how to verify delivery, and
why a correctly configured relay can still send nothing — see
[Email configuration][admin-guide] in the admin guide. This page covers only the
chart-specific wiring.

[admin-guide]: https://docs.waldur.com/latest/admin-guide/mastermind-configuration/email/

## Values

All keys below live under `waldur.mail`.

| Key        | Rendered as              | Notes                              |
|------------|--------------------------|------------------------------------|
| `host`     | `EMAIL_HOST`             | SMTP relay hostname                |
| `port`     | `EMAIL_PORT`             | Defaults to `25` when empty        |
| `username` | `EMAIL_HOST_USER`        | Stored in `waldur-secret`          |
| `password` | `EMAIL_HOST_PASSWORD`    | Stored in `waldur-secret`          |
| `useTLS`   | `EMAIL_USE_TLS`          | STARTTLS; pair with port `587`     |
| `useSSL`   | `EMAIL_USE_SSL`          | Implicit TLS; pair with port `465` |
| `from`     | `DEFAULT_FROM_EMAIL`     | `From` on outgoing mail            |
| `replyTo`  | `DEFAULT_REPLY_TO_EMAIL` | `Reply-To` header                  |
| `hookFrom` | `EMAIL_HOOK_FROM_EMAIL`  | `From` for event-logging hooks     |

`useTLS` and `useSSL` are mutually exclusive — setting both makes Django raise at
send time.

## Authenticated relay

```yaml
waldur:
  mail:
    host: "smtp.example.com"
    port: "587"
    useTLS: "true"
    username: "waldur@example.com"
    password: "s3cret"
    from: "waldur@example.com"
    replyTo: "support@example.com"
```

The credentials are base64-encoded into the chart-managed `waldur-secret` and
reach the pods as the `EMAIL_USER` / `EMAIL_PASSWORD` environment variables. They
are deliberately not interpolated into the ConfigMap, which is stored in
plaintext.

`useTLS` and `useSSL` are rendered through Helm's `camelcase`, so quote them:
`"true"` / `"false"`.

## Using an existing secret

To keep credentials out of `values.yaml` — for example when they are managed by
an external secrets operator — reference a secret you create yourself:

```yaml
waldur:
  mail:
    host: "smtp.example.com"
    port: "587"
    useTLS: "true"
    existingSecret:
      name: "smtp-credentials"
      userKey: "username"
      passwordKey: "password"
```

Leave `waldur.mail.username` and `waldur.mail.password` unset in this case;
`existingSecret.name` takes precedence over the chart-managed secret for both
keys.

Both key references are marked `optional`, so a secret carrying only one of the
two will not stop the pods from starting — the missing variable is simply absent
and the SMTP session is anonymous. If authentication is failing, confirm both
keys exist and are named as configured:

```bash
kubectl -n waldur get secret smtp-credentials -o jsonpath='{.data}' | jq 'keys'
```

## Unauthenticated relay

Leave `username`, `password` and `existingSecret.name` unset. No credential
environment variables are emitted and Waldur connects anonymously:

```yaml
waldur:
  mail:
    host: "mail-relay.internal"
    port: "25"
    from: "waldur@example.com"
```

## Enabling notifications

Every notification type ships **disabled**. Configuring the relay alone produces
no mail. Enable the ones the deployment needs under `waldur.notifications`, which
is rendered into `/etc/waldur/notifications.json` and loaded at startup:

```yaml
waldur:
  notifications:
    users.invitation_created: true
    users.invitation_approved: true
    marketplace.notification_usages: true
```

Keys not listed keep their current value. They can also be toggled at runtime
under **Administration → Notifications** in the UI.

## Verifying

```bash
kubectl -n waldur exec -it \
  $(kubectl -n waldur get pods -l app=waldur-mastermind-api -o name | head -1) \
  -- waldur sendtestemail you@example.org
```

This bypasses the notification system, so it isolates the transport half.
Messages Waldur composes are recorded regardless of relay outcome and can be
browsed under **Support → Email logs**.
