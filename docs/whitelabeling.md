# White-labeling instructions

To setup white-labeling, you can define next variables in `waldur/values.yaml` file:

* `shortPageTitle` - custom prefix for page title
* `modePageTitle` - custom page title
* `loginLogoUrl` - URL to custom image for login page (sample dimensions: 300x81px)
* `loginLogoPath` - path to custom `.png` image file
    for login page (should be in `waldur/` chart directory)
* `sidebarLogoUrl` - URL to custom image for sidebar header (sample dimensions: 175x48px)
* `sidebarLogoPath` - path to custom `.png` image file
    for sidebar header (should be in `waldur/` chart directory)
* `poweredByLogoUrl` - URL to custom image for "powered by" part of login page
* `poweredByLogoPath` - path to custom `.png` image file
    for "powered by" part of login page (should be in `waldur/` chart directory)
* `faviconPath` - path to custom favicon `.png` image file
* `logo96Path` - path to custom logo for mobile devices (96x96, `.png`)
* `logo144Path` - path to custom logo for mobile devices (144x144, `.png`)
* `logo192Path` - path to custom logo for mobile devices (192x192, `.png`)
* `tosHtmlPath` - path to custom terms of service file (`tos.html`)
* `privacyHtmlPath` - path to custom privacy statement file (`privacy.html`)

**NB:**

* the `*Path` values take place only if respectful `*Url` values are not specified.
    If both types are defined, the precedence is taken by `URL`(`*Url`) for all cases.
* all of imported files must be within chart root directory
