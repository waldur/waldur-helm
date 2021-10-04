# SAML2 configuration

To configure SAML2 for Waldur:

1. Enable SAML2 support in `values.yaml`:
    add `SAML2` string into `waldur.authMethods` list
1. Set source directory in `waldur.saml2.dir`
1. Place necessary files in the directory
    with the following manner (`.` is the source directory root):
    - `sp.crt` -> `./`
    - `sp.pem` -> `./`
    - `saml2.conf.py` -> `./`
