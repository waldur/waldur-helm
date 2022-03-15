# TLS configuration instructions

## Let’s Encrypt setup

It you want co configure [letsencrypt](https://letsencrypt.org/)
certification, you need to:

1. Set `ingress.tls.source="letsEncrypt"` in `values.yaml`
1. Create namespace for cert-manager

```bash
kubectl create namespace cert-manager
```

1. Add repository and update repos list

```bash
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
```

1. Install cert-manager release

```bash
  helm install \
    cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.7.1 \
    --set installCRDs=true
```

1. After that, `waldur` release is ready for installation.

## Your own certificate

In case, when you want to use own certificate, you need to:

1. Set `ingress.tls.source="secret"` in `values.yaml`
1. Set `ingress.tls.secretsDir` variable to directory
    with your `tls.crt` and `tls.key` files. By default it is set to `tls`
1. After that, `waldur` release is ready for installation
