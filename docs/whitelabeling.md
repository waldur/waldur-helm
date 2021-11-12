# White-labeling instructions

To setup white-labeling, you can define next variables in `waldur/values.yaml` file:

* `shortPageTitle` - custom prefix for page title
* `modePageTitle` - custom page title
* `loginLogoPath` - path to custom `.png` image file
    for login page (should be in `waldur/` chart directory)
* `sidebarLogoPath` - path to custom `.png` image file
    for sidebar header (should be in `waldur/` chart directory)
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
