# Trusting a private CA

Waldur verifies the TLS certificate of the HTTPS servers it connects to, such
as webhook listeners (event consumer webhooks) and service provider APIs. By
default only public CAs are trusted. When such a server has a certificate
issued by a private or corporate CA, add that CA to a trust bundle and point
the Waldur containers at it.

The bundle **replaces** the default trust store, so it must hold the public
CAs as well as yours. Otherwise every connection to a server with a public
certificate fails.

## 1. Build the bundle

Start from the public CAs shipped in the running Waldur image, so the bundle
matches what Waldur trusts today, and append your CA certificate (PEM):

```bash
kubectl exec -n <namespace> deploy/waldur-mastermind-worker -- \
  python -c "import certifi; print(open(certifi.where()).read(), end='')" > ca-bundle.pem
cat my-private-ca.pem >> ca-bundle.pem
grep -c 'BEGIN CERTIFICATE' ca-bundle.pem   # well over 100, not 1
```

Several private CAs can be appended one after another. Rebuild the bundle now
and then, for example on upgrades, so that it picks up changes to the public
CAs.

## 2. Store it in the cluster

```bash
kubectl create configmap waldur-ca-bundle --from-file=ca-bundle.pem -n <namespace>
```

## 3. Mount it into the Waldur pods

Add the bundle to the API, worker and beat pods (and the Matrix bot, if it
calls such a server) in your values file, and point both trust-store
variables at it: `REQUESTS_CA_BUNDLE` is read by the HTTP client Waldur uses
for webhooks and most integrations, `SSL_CERT_FILE` by the others.

```yaml
api:
  extraVolumes: &ca-bundle-volumes
    - name: ca-bundle
      configMap:
        name: waldur-ca-bundle
  extraVolumeMounts: &ca-bundle-mounts
    - name: ca-bundle
      mountPath: /etc/waldur-ca
      readOnly: true
  extraEnvVars: &ca-bundle-env
    - name: REQUESTS_CA_BUNDLE
      value: /etc/waldur-ca/ca-bundle.pem
    - name: SSL_CERT_FILE
      value: /etc/waldur-ca/ca-bundle.pem
worker:
  extraVolumes: *ca-bundle-volumes
  extraVolumeMounts: *ca-bundle-mounts
  extraEnvVars: *ca-bundle-env
beat:
  extraVolumes: *ca-bundle-volumes
  extraVolumeMounts: *ca-bundle-mounts
  extraEnvVars: *ca-bundle-env
```

If your values file already has `api`, `worker` or `beat` sections, add the
keys to them rather than repeating the sections. Apply it with
`helm upgrade`. The worker delivers webhooks, so it is the pod that matters
for event consumer webhooks.

To replace the bundle later, recreate the ConfigMap and restart the pods:

```bash
kubectl create configmap waldur-ca-bundle --from-file=ca-bundle.pem \
  -n <namespace> --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart -n <namespace> deployment/waldur-mastermind-api \
  deployment/waldur-mastermind-worker deployment/waldur-mastermind-beat
```

## Certificate requirements

Waldur runs on Python 3.13, which checks certificates strictly. A CA
certificate in the bundle needs the `CA:TRUE` basic constraint and the
`keyCertSign` key usage. A server certificate needs a subject alternative
name for the host it is reached by and, unless it is self-signed, an
authority key identifier. Certificates from most CAs have these; ones made
by hand with old tooling sometimes do not, and then fail with
`TLS certificate verification failed.` even though their CA is in the
bundle. A self-signed server certificate can itself be added to the bundle.

Webhook listeners must also be on a public address: Waldur refuses private
and loopback addresses for webhooks, whatever the bundle holds.

## Checking it

A webhook consumer whose listener is not trusted shows the error
`TLS certificate verification failed.` in its status tooltip. Once the
bundle is in place, the next delivery attempt succeeds. If the variables
point at a file that is not there, every verified connection fails instead,
and webhooks show `Request failed: OSError.`

From a worker pod, the same check by hand:

```bash
kubectl exec -n <namespace> deploy/waldur-mastermind-worker -- \
  python -c "import requests; print(requests.head('https://listener.example.com').status_code)"
```

## Scope

The bundle applies to the pods it is mounted in, for every connection they
verify with the default trust store, not only webhooks: add only CAs you
trust for all of them. Integrations configured with their own CA
certificate, such as an OpenStack offering's certificate, keep using that
one.

## Turning verification off

The mastermind setting `VERIFY_WEBHOOK_REQUESTS = False` turns certificate
verification off for every webhook; the chart has no value for it.
Anyone who can intercept the connection can then read the events, which
carry names and email addresses, and the credentials in webhook URLs. Prefer
adding the CA to the bundle.
