# SAML2 configuration

To configure SAML2 for Waldur:

1. Enable SAML2 support in `values.yaml`:

    add `SAML2` string into `waldur.authMethods` list

2. Set source directory in `waldur.saml2.dir`

3. Place necessary files in the directory

    with the following manner (`.` is the source directory root):

    - `sp.crt` -> `./`

    - `sp.pem` -> `./`

    - `saml2.conf.py` -> `./`

## Content-Security-Policy

With the HTTP-POST binding the portal submits a form straight to the identity
provider, which the portal's Content-Security-Policy blocks unless the provider's
origin is in `form-action`. List those origins in
`waldur.homeport.csp.formAction`, or set it to `https:` for a federation with
many identity providers. See [Content-Security-Policy](content-security-policy.md).
