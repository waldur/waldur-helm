## TLS configuration instructions
### Let’s Encrypt setup
It you want co configure [letsencrypt](https://letsencrypt.org/) certification, you need to:
1. Set `ingress.tls.source="letsEncrypt"` in `values.yaml`
2. Create namespace for cert-manager
```
kubectl create namespace cert-manager
```
3. Add repository and update repos list
```
helm repo add jetstack https://charts.jetstack.io
helm repo update
```
4. Install cert-manager release
```
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v0.15.1 \
  --set installCRDs=true
```
5. After that, `waldur` release is ready for installation.
### Your own certificate
In case, when you want to use own certificate, you need to:
1. Set `ingress.tls.source="secret"` in `values.yaml`
2. Set `ingress.tls.secretsDir` variable to directory with your `tls.crt` and `tls.key` files. By default it is set to `tls`
3. After that, `waldur` release is ready for installation