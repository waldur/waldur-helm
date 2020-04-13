## White-labeling instructions
To setup white-labeling, you can define next variables in `waldur/values.yaml` file:
* `shortPageTitle` - custom prefix for page title
* `modePageTitle` - custom page title
* `loginLogoUrl` - URL to custom image for login page (sample dimensions: 300x81px)
* `loginLogoBlobPath` - path to base64-encoded custom image file for login page (should be in `waldur/` chart directory)
* `sidebarLogoUrl` - URL to custom image for sidebar header (sample dimensions: 175x48px)
* `sidebarLogoBlobPath` - path to base64-encoded custom image file for sidebar header (should be in `waldur/` chart directory)
* `poweredByLogoUrl` - URL to custom image for "powered by" part of login page 
* `poweredByLogoBlobPath` - path to base64-encoded custom image file for "powered by" part of login page (should be in `waldur/` chart directory)
* `faviconPath` - path to custom favicon image
* `faviconBlobPath` - path to base64-encoded custom favicon image
* `manifestJsonPath` - path to custom `manifest.json` file
* `logo96Path` - path to custom logo for mobile devices (96x96)
* `logo96BlobPath` - path to base64-encoded custom logo for mobile devices
* `logo144Path` - path to custom logo for mobile devices (144x144)
* `logo144BlobPath` - path to base64-encoded custom logo for mobile devices
* `logo192Path` - path to custom logo for mobile devices (192x192)
* `logo192BlobPath` - path to base64-encoded custom logo for mobile devices
* `tosHtmlPath` - path to custom terms of service file (`tos.html`) 
* `privacyHtmlPath` - path to custom privacy statement file (`privacy.html`) 

##### NB: 
- the `*BlobPath` values take place only if respectful `URL`(`*Path`) values are not specified. If both types are defined, the precedence is taken by `URL`(`*Path`) for all cases.
- all of imported files must be within chart root directory