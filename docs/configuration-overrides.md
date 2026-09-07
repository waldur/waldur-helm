# Additional settings overrides and feature flags

The chart exposes a dedicated value for most commonly configured
admin-configurable runtime settings (`waldur.support`,
`waldur.marketplace.countries`, `waldur.mail`, and so on) and most feature
flags (`waldur.features`). For anything not covered by a dedicated value, use
the two generic escape hatches below instead of running a separate one-off
job.

## Arbitrary settings overrides

`waldur.settingsOverrides` is a free-form map of
[runtime setting](https://github.com/waldur/waldur-mastermind/blob/develop/src/waldur_core/server/constance_settings.py)
names to values:

```yaml
waldur:
  settingsOverrides:
    SCIM_INBOUND_ENABLED: true
    OIDC_MATCHMAKING_BY_EMAIL: true
    WALDUR_AUTH_SOCIAL_ROLE_CLAIM: "roles"
    SERVICE_ACCESS_MODE: "both"
    MARKETPLACE_LANDING_PAGE: "Catalog"
    DISCLAIMER_AREA_TEXT: "Internal use only"
    ATLASSIAN_DEFAULT_OFFERING_ISSUE_TYPE: "Service Request"
    USER_ACTIONS_DEFAULT_EXPIRATION_REMINDERS: [30, 14, 7, 1]
```

Like `waldur.marketplace.countries`, these values are applied by the
`init-whitelabeling` post-install/post-upgrade hook: the chart becomes the
source of truth and reapplies the value on every `helm upgrade`, overwriting
any change made through the admin UI in between.

## Arbitrary feature flags

`waldur.featureFlags` is a free-form map of dotted `"section.key"` feature
names (the same keys accepted by the `load_features` management command) to
booleans:

```yaml
waldur:
  featureFlags:
    marketplace.conceal_offering_pricing_tab_in_public_view: true
    support.pricelist: true
    invitations.show_service_accounts: true
    project.estimated_cost: false
```

Unlike `waldur.settingsOverrides`, these are merged into `features.json` and applied
on every pod start, so there is no separate job to run or clean up. This also
lets you override the handful of flags the chart otherwise hardcodes, such as
`project.estimated_cost` (defaults to `true`).
