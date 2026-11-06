# White-labeling instructions

To setup white-labeling, you can define next variables in `waldur/values.yaml` file:

* `shortPageTitle` - custom prefix for page title

* `modePageTitle` - custom page title

* `loginLogoPath` - path to custom `.png` image file

    for login page (should be in `waldur/` chart directory)

* `sidebarLogoPath` - path to custom `.png` image file

    for sidebar header (should be in `waldur/` chart directory)

* `sidebarLogoDarkPath` - path to custom `.png` image file

    for sidebar header in dark mode (should be in `waldur/` chart directory)

* `poweredByLogoPath` - path to custom `.png` image file

    for "powered by" part of login page (should be in `waldur/` chart directory)

* `faviconPath` - path to custom favicon `.png` image file

* `tosHtmlPath` - path to custom terms of service file (`tos.html`)

* `privacyHtmlPath` - path to custom privacy statement file (`privacy.html`)

* `brandColor` - Hex color definition is used in HomePort landing page for login button.

* `heroImagePath` - Relative path to image rendered at hero section of HomePort landing page.

* `heroLinkLabel` - Label for link in hero section of HomePort landing page. It can be lead to support site or blog post.

* `heroLinkUrl` - Link URL in hero section of HomePort landing page.

* `siteDescription` - text at hero section of HomePort landing page.

**NB:**

* the `*Path` values take place only if respectful `*Url` values are not specified.

    If both types are defined, the precedence is taken by `URL`(`*Url`) for all cases.

* all of imported files must be within chart root directory

Alternatively, TOS and PP files content can be provided as multiline values in `tosHtml` and `privacyHtml` options respectfully.
If defined, they take precedence over the aforementioned ones.

## Settings managed by the chart

A setting the chart renders is reapplied by the `init-whitelabeling` hook on
every `helm upgrade`. Mastermind locks it: the admin UI shows it as managed by
the deployment and refuses changes, which the next upgrade would revert.
Leaving a value empty (or unset, for the booleans) leaves the setting to
administrators. Locking needs a Mastermind image whose
`override_constance_settings` has `--lock`; with an older image the rendered
settings stay editable and the next upgrade reverts changes, as before.

The chart renders only what you set. `site.name`, `currencyName`,
`whitelabeling.sidebarStyle`, `whitelabeling.disableDarkTheme`,
`whitelabeling.autoApproveUserTOS`, `enableStrictCheckAcceptingInvitation`,
`homeport.docsLink` and `support.backend` have no chart default. Two chart defaults differ from
Waldur's, and the chart makes them Waldur's defaults in `override.conf.py`
instead of rendering them, so administrators can still change them:

* the documentation link is `https://docs.waldur.com` unless
  `homeport.docsLink` is set (`""` means no link on a new install; an
  upgraded one keeps the link the previous chart stored until an
  administrator clears it);
* the support desk is off unless `support` is in `waldur.features` or
  `waldur.support.existingSecret` is set.

### Upgrading

Settings the chart no longer renders keep their current values and are
handed to administrators. Removing `support` from `waldur.features` no longer
switches the support desk off: administrators switch it in the admin UI.

A values file that copies the previous chart defaults (`site.name: Waldur`,
`currencyName: EUR`, `whitelabeling.sidebarStyle: dark`, the three booleans
set to `false`, `homeport.docsLink`, `support.backend: basic`) still sets them, so they stay rendered
and become locked. Delete the ones administrators should manage. The same
applies to `helm upgrade --reuse-values`, which carries the previous chart
defaults forward: pass your values file instead.

## Available countries

The countries offered in the organization creation dialog are set with
`waldur.marketplace.countries` — a list of ISO 3166-1 alpha-2 codes (plus the
synthetic `EU` entry):

```yaml
waldur:
  marketplace:
    countries: [EE, FI, US, JP, BR, AU]
```

By default the value is empty and the chart does not touch the setting, so a list
configured through *Administration → Branding* is preserved. Once the value is
set, the chart becomes the source of truth: it is reapplied by the
`init-whitelabeling` hook on every `helm upgrade`, and the admin UI shows it
as managed by the deployment and does not let administrators change it.
