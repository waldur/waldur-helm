# Mastermind Templates

Waldur supports custom notification templates (email subjects and bodies) via the `waldur.mastermindTemplating` values.

## Configuration

There are two ways to provide templates:

### Option 1: Inline in values.yaml

Set `waldur.mastermindTemplating.mastermindTemplates` directly:

```yaml
waldur:
  mastermindTemplating:
    mastermindTemplates:
      users/invitation_notification_message.txt: |
        Hi!
      users/invitation_notification_message.html: |
        <html>
        <head lang="en">
          <meta charset="UTF-8">
          <title>Invitation</title>
        </head>
        <body><p>Hi!</p></body>
        </html>
```

### Option 2: External file

Place your templates in a YAML file within the Helm chart directory, then point to it with `waldur.mastermindTemplating.mastermindTemplatesPath`:

```yaml
waldur:
  mastermindTemplating:
    mastermindTemplatesPath: "mastermind_templates/mastermind-templates.yaml"
```

The file at that path should have the same structure as the inline option above.

The default value of `mastermindTemplatesPath` is `mastermind_templates/mastermind-templates.yaml`. If neither option is set, no ConfigMap is created.

## Template file format

Templates are keyed by their path relative to the Waldur templates directory. The key format is:

```txt
<app_name>/<event_name>_<postfix>.<extension>
```

- `<postfix>`: either `message` or `subject`
- `<extension>`: either `txt` or `html`

Example keys:

- `users/invitation_notification_message.txt` — plain-text email body
- `users/invitation_notification_message.html` — HTML email body
- `users/invitation_notification_subject.txt` — email subject line
