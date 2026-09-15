# Additional settings overrides, feature flags, and custom roles

The chart exposes a dedicated value for most commonly configured
admin-configurable runtime settings (`waldur.support`,
`waldur.marketplace.countries`, `waldur.mail`, and so on) and most feature
flags (`waldur.features`). For anything not covered by a dedicated value, use
the generic escape hatches below instead of running a separate one-off job.

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

## Custom roles

`waldur.customRoleDescriptions` and `waldur.customRolePermissions` let you
tweak the description or add/drop individual permissions on the built-in
roles (`CUSTOMER.OWNER`, `PROJECT.ADMIN`, and so on). For a role that isn't
one of the built-in ones at all, use `waldur.customRoles` instead — a list of
full role definitions:

```yaml
waldur:
  customRoles:
    - role: CUSTOMER.AUDITOR
      scope: customer
      description: "Read-only auditor"
      permissions:
        - CUSTOMER.LIST_USERS
        - PROJECT.LIST
```

`scope` is one of the `TYPE_MAP` keys in waldur-mastermind's
`waldur_core/permissions/enums.py` (`customer`, `service_provider`,
`call_organizer`, `project`, `offering`, `resource`, `resource_project`,
`call`, `proposal`) — the chart rejects the render if it isn't. Unlike the
add/drop deltas above, `permissions` here is the role's *complete* permission
list, since there's no built-in baseline to diff against — and each name is
taken as given: a misspelled permission is silently dropped rather than
rejected, since it isn't validated against `PermissionEnum`.

This requires a waldur-mastermind image whose `initdb` step loads
`custom-roles.yaml`, shipped from `8.1.3-rc.11`; earlier images render the
value but nothing consumes it.

**Reusing a built-in role's name** (e.g. `CUSTOMER.OWNER`) is also valid, and
is how you fully replace that role's permission set rather than adding to
it — `custom-roles.yaml` is imported right after the built-in `permissions.yaml`,
so your list wins. This is a one-way handover: any permission mastermind
adds to that role in a later release is loaded and then immediately
overwritten again by your list on every deployment, until you add it
yourself.

**Removing an entry does not delete or deactivate the role.** A role loaded
this way is a system role, so the API won't delete or rename it, and there's
no equivalent of `drop_stale_permissions` for roles — it just stops being
managed. Set `is_active: false` on the entry instead (requires a
waldur-mastermind image with waldur/waldur-mastermind!6317 — earlier images
silently ignore `is_active: false`).
