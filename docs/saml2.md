## SAML2 configuration
To configure SAML2 for Waldur:
1. Enable SAML2 support in `values.yaml`: `waldur.saml2.enabled`=`true`
2. Set source directory in `waldur.saml2.dir`
3. Place necessary files in the directory with the following manner (`.` is the source directory root):
    - `sp.crt` -> `./`
    - `sp.pem` -> `./`
    - attribute-mapping-related files -> `./attribute-maps/` 
    - `saml-metadata-refresh` (for cron.hourly) -> `./cron/`  
