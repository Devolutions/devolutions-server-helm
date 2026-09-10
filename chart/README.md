# Devolutions Server Helm Chart

A Helm chart for deploying [Devolutions Server](https://devolutions.net/server/) (DVLS) on Kubernetes.

Devolutions Server is a self-hosted privileged access management (PAM) solution for managing passwords, credentials, and privileged accounts.

## Features

- **Automatic Database Migrations**: Pre-upgrade hooks scale down the deployment, run migrations, then deploy the new version
- **Environment-specific Values**: Use separate value files per environment for clean configuration management
- **TLS Support**: Integration with cert-manager for automatic certificate management
- **Gateway API / Istio Integration**: Optional HTTPRoute and DestinationRule for service mesh setups

## Prerequisites

- Kubernetes 1.32+ (tested with 1.34)
- Helm 3.17+ or v4
- A SQL Server database (Azure SQL or self-hosted)
- A TLS certificate — DVLS serves HTTPS only. Use [cert-manager](https://cert-manager.io/) for automatic management, or provide a pre-existing TLS secret via `certificate.secretName`
- [Gateway API](https://gateway-api.sigs.k8s.io/) controller (optional, for HTTPRoute ingress)
- [Istio](https://istio.io/) (optional, for DestinationRule TLS origination)

## Installation

### Add the Helm repository

```bash
helm repo add devolutions https://devolutions.github.io/helm-charts
helm repo update
```

### Release channels

The chart is published in three release channels:

| Channel | Helm version example | `--devel` required | Description |
|---------|---------------------|--------------------|-------------|
| **Stable** | `2026.1.14` | No | Production-ready releases |
| **LTS** | `2025.3.18` | No | Long-term support releases |
| **Beta** | `2026.1.3-beta` | Yes | Pre-release versions for early testing |

By default, `helm install` and `helm search` only show Stable and LTS versions. To include Beta releases, add the `--devel` flag:

```bash
# Search for all versions including beta
helm search repo devolutions/devolutions-server --devel

# Install a specific beta version
helm install dvls devolutions/devolutions-server --version 2026.1.3-beta
```

### Create the required secrets

The chart expects the following Kubernetes secrets to exist before installation. Create them using your preferred method (Terraform, Vault, sealed-secrets, etc.). The `kubectl` examples below are for illustration only.

**Docker Hub registry credentials** (referenced by `imagePullSecrets`):

```bash
kubectl create secret docker-registry docker-hub \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username='<username>' \
  --docker-password='<password>'
```

**Docker Hardened Image (DHI) registry credentials** — required when `migration.enabled` is `true` (the default), because the scale-down hook pulls `dhi.io/kubectl:1.35-compat`. Skip this if you disable migrations or override `migration.kubectl.image` to a registry you can already pull from.

```bash
kubectl create secret docker-registry dhi-io \
  --docker-server=dhi.io \
  --docker-username='<dhi-username>' \
  --docker-password='<dhi-password>'
```

Then list both pull secrets in your values file:

```yaml
imagePullSecrets:
  - name: docker-hub
  - name: dhi-io
```

**DVLS credentials** (referenced by `existingSecret`):

```bash
kubectl create secret generic devolutions-server \
  --from-literal=dvls-admin-password='<admin-password>' \
  --from-literal=dvls-encryption-config='<base64-encoded-encryption-config>' \
  --from-literal=db-username='<database-username>' \
  --from-literal=db-password='<database-password>'
```

The secret must contain the following keys:

| Key | Description |
|-----|-------------|
| `dvls-admin-password` | Admin account password |
| `dvls-encryption-config` | Base64-encoded encryption configuration |
| `db-username` | Database username |
| `db-password` | Database password |

> **Note:** The database key names `db-username` and `db-password` are defaults. You can use any key names by setting `database.usernameSecretKey` and `database.passwordSecretKey`. The DVLS container supports both `DATABASE_*` (default) and `AZURE_SQL_*` environment variable prefixes — set `database.envPrefix` to switch.

To obtain the encryption configuration, follow the [Devolutions Server first-time setup](https://docs.devolutions.net/server/kb/how-to-articles/devolutions-server-docker-deployment/#devolutions-server-first-time-setup) guide. You can select your OS at the top of the documentation page.

### Create an environment values file

Create a values file for your environment (e.g. `values-production.yaml`):

```yaml
replicaCount: 1

# Overrides the image tag whose default is the chart appVersion
image:
  tag: '2026.1.14.0'

imagePullSecrets:
  - name: docker-hub
  - name: dhi-io

dvls:
  hostname: dvls.example.com
  admin:
    email: admin@example.com

database:
  host: sqlserver.example.com
  name: dvls-db

aspnetcore:
  environment: Production

certificate:
  issuerName: letsencrypt
  secretName: cert-dvls-example-com

# Optional: Gateway API HTTPRoute
httproute:
  enabled: true
  gateway:
    name: my-gateway
    namespace: istio-system
    sectionName: https-dvls

# Optional: Istio DestinationRule for TLS origination
destinationRule:
  enabled: true

nodeSelector:
  workload: apps

existingSecret: devolutions-server
```

### Install the chart

```bash
helm upgrade --install dvls devolutions/devolutions-server \
  -f values-production.yaml \
  -n devolutions-server --create-namespace \
  --wait --timeout 15m
```

## Previewing Changes

Before applying changes, you can preview what will be modified using the [helm-diff plugin](https://github.com/databus23/helm-diff) (requires Helm 3.17+ or 4.x):

```bash
helm diff upgrade dvls devolutions/devolutions-server \
  -f values-production.yaml \
  -n devolutions-server
```

## Upgrading

The chart includes pre-upgrade migration hooks. When `migration.enabled=true` (the default), the upgrade process:

1. **RBAC setup** (hook weight -15): Creates ServiceAccount, Role, and RoleBinding for migration jobs
2. **Scale down** (hook weight -10): Scales deployment to 0 replicas and waits for pods to terminate
3. **Migration** (hook weight -5): Runs database migration with `DVLS_UPDATE_MODE=true`
4. **Deploy**: Updates deployment with new image version

To upgrade, update the `image.tag` in your values file and run:

```bash
helm upgrade dvls devolutions/devolutions-server \
  -f values-production.yaml \
  -n devolutions-server \
  --wait --timeout 15m
```

Use `--wait` so Helm only returns when the Deployment is ready (based on the readiness probe).

### Skipping Migrations

For hotfixes that don't require database changes:

```bash
helm upgrade dvls devolutions/devolutions-server \
  -f values-production.yaml \
  --set migration.enabled=false \
  -n devolutions-server \
  --wait --timeout 15m
```

### Rollback

```bash
helm rollback dvls -n devolutions-server
```

> **Note:** If the upgrade included a database migration, you must restore the database from a snapshot **before** rolling back the image. See [Migration job failing](#migration-job-failing) for details.

## Values Reference

### Image

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `devolutions/devolutions-server` |
| `image.tag` | Image tag (defaults to `appVersion`) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Image pull secrets | `[]` |

### General

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override release fullname | `""` |
| `selectorLabels` | Override selector labels (for migration from existing releases) | `{}` |

### DVLS Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `dvls.hostname` | External hostname for DVLS (**required**) | `""` |
| `dvls.admin.username` | Admin username | `dvls-admin` |
| `dvls.admin.email` | Admin email address | `""` |
| `dvls.admin.passwordSecretKey` | Key in `existingSecret` for admin password | `dvls-admin-password` |
| `dvls.path` | DVLS path inside container | `/opt/devolutions/dvls` |
| `dvls.telemetry` | Enable telemetry | `false` |
| `dvls.encryptionConfigSecretKey` | Key in `existingSecret` for encryption config | `dvls-encryption-config` |

### Database

| Parameter | Description | Default |
|-----------|-------------|---------|
| `database.host` | SQL Server hostname (**required**) | `""` |
| `database.name` | Database name (**required**) | `""` |
| `database.port` | Database port | `1433` |
| `database.envPrefix` | Environment variable prefix (`DATABASE` or `AZURE_SQL`) | `DATABASE` |
| `database.usernameSecretKey` | Key in `existingSecret` for DB username | `db-username` |
| `database.passwordSecretKey` | Key in `existingSecret` for DB password | `db-password` |

### TLS Certificate

| Parameter | Description | Default |
|-----------|-------------|---------|
| `certificate.enabled` | Create a cert-manager Certificate resource | `true` |
| `certificate.name` | Certificate resource name | `<release>-tls` |
| `certificate.secretName` | TLS secret name | `<release>-tls` |
| `certificate.issuerName` | cert-manager ClusterIssuer name (**required** when certificate enabled) | `""` |
| `certificate.issuerKind` | Issuer kind | `ClusterIssuer` |
| `certificate.privateKeyRotationPolicy` | Private key rotation policy | `Always` |

### Networking

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `5000` |
| `service.targetPort` | Container target port | `5000` |
| `httproute.enabled` | Create a Gateway API HTTPRoute | `false` |
| `httproute.gateway.name` | Gateway name | `""` |
| `httproute.gateway.namespace` | Gateway namespace | `""` |
| `httproute.gateway.sectionName` | Gateway section name | `""` |
| `backendTLSPolicy.enabled` | Create a Gateway API BackendTLSPolicy | `false` |
| `backendTLSPolicy.wellKnownCACertificates` | Use well-known CAs (e.g., `System`) | `""` |
| `backendTLSPolicy.caCertificateRefs` | CA certificate refs for backend TLS validation | `[]` |
| `destinationRule.enabled` | Create an Istio DestinationRule | `false` |

### Resources and Scheduling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `nodeSelector` | Node selector labels | `{}` |
| `affinity` | Affinity rules | `{}` |
| `tolerations` | Tolerations | `[]` |
| `topologySpreadConstraints` | Topology spread constraints | `[]` |
| `strategy.type` | Deployment strategy | `Recreate` |

### Migration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `migration.enabled` | Enable pre-upgrade migration hook | `true` |
| `migration.image.repository` | Migration image (defaults to main image) | `""` |
| `migration.image.tag` | Migration image tag (defaults to main tag) | `""` |
| `migration.kubectl.image` | kubectl image for scale-down job (DHI requires `imagePullSecrets` for `dhi.io`) | `dhi.io/kubectl` |
| `migration.kubectl.tag` | kubectl image tag — `-compat` variant is required because the hook runs `/bin/sh`; pin to your cluster's Kubernetes minor (current or n-1) | `1.35-compat` |
| `migration.activeDeadlineSeconds` | Migration job deadline (seconds) | `600` |
| `migration.backoffLimit` | Job backoff limit | `0` |
| `migration.ttlSecondsAfterFinished` | Job TTL after completion | `604800` |
| `migration.backupPath` | Backup mount path | `/backup` |
| `migration.backupVolumeSizeLimit` | Backup volume size | `2Gi` |

### Security

| Parameter | Description | Default |
|-----------|-------------|---------|
| `existingSecret` | Name of the Kubernetes secret | `devolutions-server` |
| `podSecurityContext.fsGroup` | Pod filesystem group | `1000` |
| `securityContext.runAsNonRoot` | Run as non-root | `true` |
| `securityContext.runAsUser` | Run as user ID | `1000` |
| `securityContext.runAsGroup` | Run as group ID | `1000` |
| `securityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |
| `securityContext.capabilities.drop` | Linux capabilities to drop | `["ALL"]` |
| `securityContext.seccompProfile.type` | Seccomp profile type | `RuntimeDefault` |

## Image Signature Verification

Devolutions Server container images are signed with [Notation](https://notaryproject.dev/) using the Devolutions EV code signing certificate issued by GlobalSign. Signatures are COSE, attached as OCI 1.1 referrers (no separate `.sig` tag), and RFC 3161 timestamped against the GlobalSign TSA.

### Manual verification

Install the [notation CLI](https://notaryproject.dev/docs/user-guides/installation/cli/), then add the GlobalSign code signing chain to a trust store:

```bash
cat > globalsign-codesign-chain.pem <<'EOF'
-----BEGIN CERTIFICATE-----
MIIG6DCCBNCgAwIBAgIQd70OBbdZC7YdR2FTHj917TANBgkqhkiG9w0BAQsFADBT
MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEpMCcGA1UE
AxMgR2xvYmFsU2lnbiBDb2RlIFNpZ25pbmcgUm9vdCBSNDUwHhcNMjAwNzI4MDAw
MDAwWhcNMzAwNzI4MDAwMDAwWjBcMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xv
YmFsU2lnbiBudi1zYTEyMDAGA1UEAxMpR2xvYmFsU2lnbiBHQ0MgUjQ1IEVWIENv
ZGVTaWduaW5nIENBIDIwMjAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
AQDLIO+XHrkBMkOgW6mKI/0gXq44EovKLNT/QdgaVdQZU7f9oxfnejlcwPfOEaP5
pe0B+rW6k++vk9z44rMZTIOwSkRQBHiEEGqk1paQjoH4fKsvtaNXM9JYe5QObQ+l
kSYqs4NPcrGKe2SS0PC0VV+WCxHlmrUsshHPJRt9USuYH0mjX/gTnjW4AwLapBMv
hUrvxC9wDsHUzDMS7L1AldMRyubNswWcyFPrUtd4TFEBkoLeE/MHjnS6hICf0qQV
Duiv6/eJ9t9x8NG+p7JBMyB1zLHV7R0HGcTrJnfyq20Xk0mpt+bDkJzGuOzMyXua
XsXFJJNjb34Qi2HPmFWjJKKINvL5n76TLrIGnybADAFWEuGyip8OHtyYiy7P2uKJ
NKYfJqCornht7KGIFTzC6u632K1hpa9wNqJ5jtwNc8Dx5CyrlOxYBjk2SNY7Wugi
znQOryzxFdrRtJXorNVJbeWv3ZtrYyBdjn47skPYYjqU5c20mLM3GSQScnOrBLAJ
3IXm1CIE70AqHS5tx2nTbrcBbA3gl6cW5iaLiPcDRIZfYmdMtac3qFXcAzaMbs9t
NibxDo+wPXHA4TKnguS2MgIyMHy1k8gh/TyI5mlj+O51yYvCq++6Ov3pXr+2EfG+
8D3KMj5ufd4PfpuVxBKH5xq4Tu4swd+hZegkg8kqwv25UwIDAQABo4IBrTCCAakw
DgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMBIGA1UdEwEB/wQI
MAYBAf8CAQAwHQYDVR0OBBYEFCWd0PxZCYZjxezzsRM7VxwDkjYRMB8GA1UdIwQY
MBaAFB8Av0aACvx4ObeltEPZVlC7zpY7MIGTBggrBgEFBQcBAQSBhjCBgzA5Bggr
BgEFBQcwAYYtaHR0cDovL29jc3AuZ2xvYmFsc2lnbi5jb20vY29kZXNpZ25pbmdy
b290cjQ1MEYGCCsGAQUFBzAChjpodHRwOi8vc2VjdXJlLmdsb2JhbHNpZ24uY29t
L2NhY2VydC9jb2Rlc2lnbmluZ3Jvb3RyNDUuY3J0MEEGA1UdHwQ6MDgwNqA0oDKG
MGh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vY29kZXNpZ25pbmdyb290cjQ1LmNy
bDBVBgNVHSAETjBMMEEGCSsGAQQBoDIBAjA0MDIGCCsGAQUFBwIBFiZodHRwczov
L3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzAHBgVngQwBAzANBgkqhkiG
9w0BAQsFAAOCAgEAJXWgCck5urehOYkvGJ+r1usdS+iUfA0HaJscne9xthdqawJP
sz+GRYfMZZtM41gGAiJm1WECxWOP1KLxtl4lC3eW6c1xQDOIKezu86JtvE21PgZL
yXMzyggULT1M6LC6daZ0LaRYOmwTSfilFQoUloWxamg0JUKvllb0EPokffErcsEW
4Wvr5qmYxz5a9NAYnf10l4Z3Rio9I30oc4qu7ysbmr9sU6cUnjyHccBejsj70yqS
M+pXTV4HXsrBGKyBLRoh+m7Pl2F733F6Ospj99UwRDcy/rtDhdy6/KbKMxkrd23b
ywXwfl91LqK2vzWqNmPJzmTZvfy8LPNJVgDIEivGJ7s3r1fvxM8eKcT04i3OKmHP
V+31CkDi9RjWHumQL8rTh1+TikgaER3lN4WfLmZiml6BTpWsVVdD3FOLJX48YQ+K
C7r1P6bXjvcEVl4hu5/XanGAv5becgPY2CIr8ycWTzjoUUAMrpLvvj1994DGTDZX
hJWnhBVIMA5SJwiNjqK9IscZyabKDqh6NttqumFfESSVpOKOaO4ZqUmZXtC0NL3W
+UDHEJcxUjk1KRGHJNPE+6ljy3dI1fpi/CTgBHpO0ORu3s6eOFAm9CFxZdcJJdTJ
BwB6uMfzd+jF1OJV0NMe9n9S4kmNuRFyDIhEJjNmAUTf5DMOId5iiUgH2vU=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFcjCCA1qgAwIBAgIQdlP+rHVGSJP15ddKSDpO+DANBgkqhkiG9w0BAQwFADBT
MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEpMCcGA1UE
AxMgR2xvYmFsU2lnbiBDb2RlIFNpZ25pbmcgUm9vdCBSNDUwHhcNMjAwMzE4MDAw
MDAwWhcNNDUwMzE4MDAwMDAwWjBTMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xv
YmFsU2lnbiBudi1zYTEpMCcGA1UEAxMgR2xvYmFsU2lnbiBDb2RlIFNpZ25pbmcg
Um9vdCBSNDUwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2LcUw3Xro
q5A9A3KwOkuZFmGy5f+lZx03HOV+7JODqoT1o0ObmEWKuGNXXZsAiAQl6fhokkuC
2EvJSgPzqH9qj4phJ72hRND99T8iwqNPkY2zBbIogpFd+1mIBQuXBsKY+CynMyTu
UDpBzPCgsHsdTdKoWDiW6d/5G5G7ixAs0sdDHaIJdKGAr3vmMwoMWWuOvPSrWpd7
f65V+4TwgP6ETNfiur3EdaFvvWEQdESymAfidKv/aNxsJj7pH+XgBIetMNMMjQN8
VbgWcFwkeCAl62dniKu6TjSYa3AR3jjK1L6hwJzh3x4CAdg74WdDhLbP/HS3L4Sj
v7oJNz1nbLFFXBlhq0GD9awd63cNRkdzzr+9lZXtnSuIEP76WOinV+Gzz6ha6Qcl
mxLEnoByPZPcjJTfO0TmJoD80sMD8IwM0kXWLuePmJ7mBO5Cbmd+QhZxYucE+WDG
ZKG2nIEhTivGbWiUhsaZdHNnMXqR8tSMeW58prt+Rm9NxYUSK8+aIkQIqIU3zgdh
VwYXEiTAxDFzoZg1V0d+EDpF2S2kUZCYqaAHN8RlGqocaxZ396eX7D8ZMJlvMfvq
QLLn0sT6ydDwUHZ0WfqNbRcyvvjpfgP054d1mtRKkSyFAxMCK0KA8olqNs/ITKDO
nvjLja0Wp9Pe1ZsYp8aSOvGCY/EuDiRk3wIDAQABo0IwQDAOBgNVHQ8BAf8EBAMC
AYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUHwC/RoAK/Hg5t6W0Q9lWULvO
ljswDQYJKoZIhvcNAQEMBQADggIBAF4runSXNERfdkgoQIST7gFu6aGz1oAl5nvk
vAmRPQ/8dq3X1DAgu49g0JHWHPKc73gaK5QyAsEkllJSAtDz0fzymzlumeEfjkNB
fZoeW8ldmoT8JuaH83RyJq2kG9k9O2pSoDwJHi8ee7MztEXH96yxr5NgrXauuLIV
eOuDauv/20arJOXuAvqQH1nAL13Wt12kXBC3clP4QU7M+ngaJUrK/oViQ2HDtDeq
gdL01joPvY1ZfjBH3itr5yFQM1/UZ5vUuGefPCeZA/+FQ45zEsogzehh1bFm3BfW
OW0P288jN6GCiU4caz/WoM2qB50+Qiaq1wzu+ke/GlJ+0XWB08mKYhdtT4igIaAm
Pq9t2WIwH+mYKK5ujdWOTHJmk4CNKuNVx2BnkEJWXCJRD7PcTjnuTd3ZHXgQVDtu
0JdvA7UesiNzxhKymmTQ/JWFJKj/36Gw3JFArt8JM6u53ZK38cyRdDtp62eXG5C/
58egb3G7V7+3j1rtekBqFs2AhC0v4QLUJJRDsxX8DCsb/XFv/Mu8dRc6XoPSybMv
G9WcjX9U/n5+5Fajh6ed4VlSlEGPbVu+hpWa/xp23UDSUUpwtB8zYyN3P+wnHlnk
CIftNIJKDz/+oB3B9WdzRYZ49Kop6SeHxhnbxhMUwzlJh02gl+BlE/Wdd1bp2rNY
xzrywM2C
-----END CERTIFICATE-----
EOF

notation cert add --type ca --store devolutions globalsign-codesign-chain.pem
```

The chain alone would trust every GlobalSign EV code signing certificate, so pin `trustedIdentities` to the Devolutions subject:

```bash
cat > trustpolicy.json <<'EOF'
{
  "version": "1.0",
  "trustPolicies": [
    {
      "name": "devolutions-server",
      "registryScopes": [ "docker.io/devolutions/devolutions-server" ],
      "signatureVerification": { "level": "strict" },
      "trustStores": [ "ca:devolutions", "tsa:globalsign" ],
      "trustedIdentities": [ "x509.subject: C=CA, ST=Quebec, L=Lavaltrie, O=DEVOLUTIONS INC., CN=DEVOLUTIONS INC." ]
    }
  ]
}
EOF

notation policy import trustpolicy.json
```

Signatures are timestamped, so the timestamping authority needs its own trust store. Without it the signature stops verifying once the signing certificate expires:

```bash
cat > globalsign-root-r6.pem <<'EOF'
-----BEGIN CERTIFICATE-----
MIIFgzCCA2ugAwIBAgIORea7A4Mzw4VlSOb/RVEwDQYJKoZIhvcNAQEMBQAwTDEg
MB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjYxEzARBgNVBAoTCkdsb2Jh
bFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTQxMjEwMDAwMDAwWhcNMzQx
MjEwMDAwMDAwWjBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSNjET
MBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCAiIwDQYJ
KoZIhvcNAQEBBQADggIPADCCAgoCggIBAJUH6HPKZvnsFMp7PPcNCPG0RQssgrRI
xutbPK6DuEGSMxSkb3/pKszGsIhrxbaJ0cay/xTOURQh7ErdG1rG1ofuTToVBu1k
ZguSgMpE3nOUTvOniX9PeGMIyBJQbUJmL025eShNUhqKGoC3GYEOfsSKvGRMIRxD
aNc9PIrFsmbVkJq3MQbFvuJtMgamHvm566qjuL++gmNQ0PAYid/kD3n16qIfKtJw
LnvnvJO7bVPiSHyMEAc4/2ayd2F+4OqMPKq0pPbzlUoSB239jLKJz9CgYXfIWHSw
1CM69106yqLbnQneXUQtkPGBzVeS+n68UARjNN9rkxi+azayOeSsJDa38O+2HBNX
k7besvjihbdzorg1qkXy4J02oW9UivFyVm4uiMVRQkQVlO6jxTiWm05OWgtH8wY2
SXcwvHE35absIQh1/OZhFj931dmRl4QKbNQCTXTAFO39OfuD8l4UoQSwC+n+7o/h
bguyCLNhZglqsQY6ZZZZwPA1/cnaKI0aEYdwgQqomnUdnjqGBQCe24DWJfncBZ4n
WUx2OVvq+aWh2IMP0f/fMBH5hc8zSPXKbWQULHpYT9NLCEnFlWQaYw55PfWzjMpY
rZxCRXluDocZXFSxZba/jJvcE+kNb7gu3GduyYsRtYQUigAZcIN5kZeR1Bonvzce
MgfYFGM8KEyvAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTAD
AQH/MB0GA1UdDgQWBBSubAWjkxPioufi1xzWx/B/yGdToDAfBgNVHSMEGDAWgBSu
bAWjkxPioufi1xzWx/B/yGdToDANBgkqhkiG9w0BAQwFAAOCAgEAgyXt6NH9lVLN
nsAEoJFp5lzQhN7craJP6Ed41mWYqVuoPId8AorRbrcWc+ZfwFSY1XS+wc3iEZGt
Ixg93eFyRJa0lV7Ae46ZeBZDE1ZXs6KzO7V33EByrKPrmzU+sQghoefEQzd5Mr61
55wsTLxDKZmOMNOsIeDjHfrYBzN2VAAiKrlNIC5waNrlU/yDXNOd8v9EDERm8tLj
vUYAGm0CuiVdjaExUd1URhxN25mW7xocBFymFe944Hn+Xds+qkxV/ZoVqW/hpvvf
cDDpw+5CRu3CkwWJ+n1jez/QcYF8AOiYrg54NMMl+68KnyBr3TsTjxKM4kEaSHpz
oHdpx7Zcf4LIHv5YGygrqGytXm3ABdJ7t+uA/iU3/gKbaKxCXcPu9czc8FB10jZp
nOZ7BN9uBmm23goJSFmH63sUYHpkqmlD75HHTOwY3WzvUy2MmeFe8nI+z1TIvWfs
pA9MRf/TuTAjB0yPEL+GltmZWrSZVxykzLsViVO6LAUP5MSeGbEYNNVMnbrt9x+v
JJUEeKgDu+6B5dpffItKoZB0JaezPkvILFa9x8jvOOJckvB595yEunQtYQEgfn7R
8k8HWV+LLUNS60YMlOH1Zkd5d9VUWx+tJDfLRVpOoERIyNiwmcUVhAn21klJwGW4
5hpxbqCo8YLoRT5s1gLXCmeDBVrJpBA=
-----END CERTIFICATE-----
EOF

notation cert add --type tsa --store globalsign globalsign-root-r6.pem
```

Verify by digest rather than by tag, since a tag can be moved after you read it:

```bash
DIGEST=$(docker buildx imagetools inspect devolutions/devolutions-server:<tag> --format '{{json .Manifest.Digest}}' | tr -d '"')

notation verify devolutions/devolutions-server@$DIGEST
```

### Kyverno policy

If you use [Kyverno](https://kyverno.io/), you can enforce image signature verification at the cluster level with an `ImageValidatingPolicy`. The example below audits pods in a specific namespace — change `validationActions` to `["Deny"]` to block unsigned images.

The `notary` attestor does not expose `trustedIdentities`, so trust is pinned to the Devolutions signing certificates themselves rather than to the CA chain. Two certificates are listed so signatures stay verifiable across a certificate rotation. `tsaCerts` holds the root of the timestamping authority.

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: verify-dvls-image-signatures
spec:
  webhookConfiguration:
    timeoutSeconds: 15
  evaluation:
    background:
      enabled: true
  validationActions: ["Audit"]
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: devolutions-server    # adjust to your namespace
  matchImageReferences:
    - glob: "devolutions/devolutions-server:*"
    - glob: "devolutions/devolutions-server@*"
  credentials:
    secrets: ["docker-hub"]    # your Docker Hub pull secret, in the Kyverno namespace
  attestors:
    - name: notary
      notary:
        certs:
          value: |
            -----BEGIN CERTIFICATE-----
            MIIHsTCCBZmgAwIBAgIMc9PDNgP/i7RCJPJeMA0GCSqGSIb3DQEBCwUAMFwxCzAJBgNVBAYTAkJF
            MRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdDQyBSNDUg
            RVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDAeFw0yMzEwMzAxNzUxMThaFw0yNjEwMzAxNzUxMThaMIHx
            MR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjETMBEGA1UEBRMKMTE2MjU0NDY4OTETMBEG
            CysGAQQBgjc8AgEDEwJDQTEXMBUGCysGAQQBgjc8AgECEwZRdWViZWMxCzAJBgNVBAYTAkNBMQ8w
            DQYDVQQIEwZRdWViZWMxEjAQBgNVBAcTCUxhdmFsdHJpZTEYMBYGA1UEChMPRGV2b2x1dGlvbnMg
            SW5jMRgwFgYDVQQDEw9EZXZvbHV0aW9ucyBJbmMxJzAlBgkqhkiG9w0BCQEWGHNlY3VyaXR5QGRl
            dm9sdXRpb25zLm5ldDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJ8OTpzV4Iv2tO+r
            UPWWrUaZTTxkrJhAlDsRv+ZEWlFeqk4WLJKd/wHKxhtnjLgyciXszZaNzmfUlxdH0E9aaQkucjus
            VPCmr87nEpTBbbT8RjI64XtNqxGrqiWWObvd1wuOu3nP9ra7aA768xLwtVjpRcoAZkYiKAyg9L3Z
            /YySQqZ0SYDl2nBsAtR+8f2zLSqSdR9Bjp2yWkjw9uNMLH0ZjnGoJMy0FBxYHmwGf8jRgCWnnK46
            f7aBri9Ry5wBlNWx6hEj8myfkpZZvSIz3Ctu/4M4LNwC0EX5iPYqnzAdFZ8wK6a7hi5hzBNjeFsi
            41GhSLyPicum2MZrPtHdR8Cvhv+sfhWDz+X258/rVntulKRlsiWeHcaPL1QkKPDnCC5C5yeWVJs0
            2DlkF3u/cNFQrAq/MX1Nig4RHAZ15jy5Lh+dJg/te4YX1v5yhn8PmC4Zp5uIkkSh1EmQZ2I/k/7q
            Ms7jd3OCYHiGZZu4XnCh9Fhd3WKEU5/hoEfarMecWQO+nnN5yUyWCgu7ElVviZTfpnzgqcm5Pt89
            OEr1Fs0Sio8/N3UFhwJxGZVosJgfD7oCCZVebduAKy/jMz8OqTJx89fXWwFd51h1Mni2KG0WjV5G
            p9CxcSK835djBQgn8R18dSZodT7t5iGBI9XKc+b0WrWYAALcqof7pG0ikSalAgMBAAGjggHbMIIB
            1zAOBgNVHQ8BAf8EBAMCB4AwgZ8GCCsGAQUFBwEBBIGSMIGPMEwGCCsGAQUFBzAChkBodHRwOi8v
            c2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9nc2djY3I0NWV2Y29kZXNpZ25jYTIwMjAuY3J0
            MD8GCCsGAQUFBzABhjNodHRwOi8vb2NzcC5nbG9iYWxzaWduLmNvbS9nc2djY3I0NWV2Y29kZXNp
            Z25jYTIwMjAwVQYDVR0gBE4wTDBBBgkrBgEEAaAyAQIwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93
            d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wBwYFZ4EMAQMwCQYDVR0TBAIwADBHBgNVHR8E
            QDA+MDygOqA4hjZodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNh
            MjAyMC5jcmwwIwYDVR0RBBwwGoEYc2VjdXJpdHlAZGV2b2x1dGlvbnMubmV0MBMGA1UdJQQMMAoG
            CCsGAQUFBwMDMB8GA1UdIwQYMBaAFCWd0PxZCYZjxezzsRM7VxwDkjYRMB0GA1UdDgQWBBT5ymf4
            g+pZGcTmsd4j5s7xv9fz2jANBgkqhkiG9w0BAQsFAAOCAgEAGvu6RRlge5FgpvQl2hWH0vCeCfjm
            b8EGD3SNMvkIXpk/jFgHaRoo3frqx8Bu+YpOFuB9wi83bo2NLX9wVdp3lp/qzk7MZSJz6YAVk6Fu
            lfzUZ52wCfGXUPgEomzb6JaH94ra9tr8rcnlXZntLtgWAeoXS+WYO03GcFDyOwjfTOtty5gmjB+3
            xYuN9biGvRJ0AiTYXhfUJMaG0lUy49zHJS6+uaSenWDbL32Nzl5cDqqnQKJRsULVHcLWSllhPizG
            K7zoHeRtjompM7Z/Ty2O+mKHfpR4UIL8HJkHNvUPwUUhoqISuOUMdUwgEJjVesQQMQmkjIxHKhte
            wi6KzKfhOkrwmpFvQLSikPO8TwGUq+qWqYd9p9s5RcUfmDP8X1qIkAx8fKHh11SD2cVwX5gpYqny
            Gl1ohb7mm2WwLYtJLm3O0xRdGKxR//MJN4tDYwBdztWXSxzxkP1Spv3Cb62Yrdka+cMoKKTATxhT
            7L3qiAVTJsZwRZdRiTdC+5cp5LT3+/pA7BuBjejkSSs1DI9S6AjYezJa2YuFN0Mz8+eP47Y0M2Q9
            e8aKyzZvQ7zJQxWSH0LQcbhZLcv8TGgzWR43Vh3ngVoWGTXNC/cpBoLswlTy5muasgks810Q8YqI
            V8jwIshX/TiMAitH4DhINoKkNPP5cNkXuQ/jYobJsmJIPWo=
            -----END CERTIFICATE-----
            -----BEGIN CERTIFICATE-----
            MIIHszCCBZugAwIBAgIMTBZCMes1fh+PwkUoMA0GCSqGSIb3DQEBCwUAMFwxCzAJBgNVBAYTAkJF
            MRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdDQyBSNDUg
            RVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDAeFw0yNTEyMDQyMTAyMjRaFw0yODEyMDQyMTAyMjRaMIHz
            MR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjETMBEGA1UEBRMKMTE2MjU0NDY4OTETMBEG
            CysGAQQBgjc8AgEDEwJDQTEXMBUGCysGAQQBgjc8AgECEwZRdWViZWMxCzAJBgNVBAYTAkNBMQ8w
            DQYDVQQIEwZRdWViZWMxEjAQBgNVBAcTCUxhdmFsdHJpZTEZMBcGA1UEChMQREVWT0xVVElPTlMg
            SU5DLjEZMBcGA1UEAxMQREVWT0xVVElPTlMgSU5DLjEnMCUGCSqGSIb3DQEJARYYc2VjdXJpdHlA
            ZGV2b2x1dGlvbnMubmV0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAq8ZKamwIPGJX
            h9qmwU8JWE0yl92WCvMWEKJedfQbLtm7Z7twMyXZE2jQfyGko0eFI4OSC5Zg0tl+Yz5um8TYVss3
            ShjFSaUQeIFlY3z7R2rXTJuR9Bmn4773lLeZfd5x0pMGE9gHsjkdg1YE9HUC7zpjrzH4sFpO0zcB
            j/O/AHaAxt59mwoBr0v2enWXtSM3qp9myRAb7NHEKP7zwKDqyuQJjI278sycW1YidtvG6qSHV11N
            MCZVVJQ5def68q1QTaFPD/bnHemxscsuBwturQThnDOZE8Hamz3vZqi4RoyQ+Fhc7gpO1NkWPoah
            jLawBRobGA+AAMR5lj+C6GpIEA2efZZrqNqhyAy+82FIl3tpB+V2+mzRlDJ6tWtrvOCipPQmTIs0
            eb0AqI1X6YlAeqKtfEv5jvS87i4UlW6TK9x4074L7LRF7vulvwGe1F+5I51zJKPW/81Dt4cBXr/N
            jbXGVizAjPu7KygdB5kQxaURfxuMk2MO+RPUFQX2PrnmFV7LGlnO9pKAt2l2llVI5DNKR2IfQo6E
            GJD1Hk+lrb9b2qF0s2L6wqOvX/EQpI53V8UbnpGI3h6az1h0RBH0qucatWlBDRApK62oWJZSVSoK
            Ba4PBM97ZX5S8drbECVmVtgDMZ9fxzo4ieIUuNZzFcpXbVHtU/xR9DGt/fw9qkkCAwEAAaOCAdsw
            ggHXMA4GA1UdDwEB/wQEAwIHgDCBnwYIKwYBBQUHAQEEgZIwgY8wTAYIKwYBBQUHMAKGQGh0dHA6
            Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0L2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNhMjAyMC5j
            cnQwPwYIKwYBBQUHMAGGM2h0dHA6Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rl
            c2lnbmNhMjAyMDBVBgNVHSAETjBMMEEGCSsGAQQBoDIBAjA0MDIGCCsGAQUFBwIBFiZodHRwczov
            L3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzAHBgVngQwBAzAJBgNVHRMEAjAAMEcGA1Ud
            HwRAMD4wPKA6oDiGNmh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vZ3NnY2NyNDVldmNvZGVzaWdu
            Y2EyMDIwLmNybDAjBgNVHREEHDAagRhzZWN1cml0eUBkZXZvbHV0aW9ucy5uZXQwEwYDVR0lBAww
            CgYIKwYBBQUHAwMwHwYDVR0jBBgwFoAUJZ3Q/FkJhmPF7POxEztXHAOSNhEwHQYDVR0OBBYEFBz0
            BXTVeq8fOSR5EOPQV6iQY+fAMA0GCSqGSIb3DQEBCwUAA4ICAQC67LrgjleBhagrOdc4rMExTPg1
            Mae/Vw3yi9f2kmVVR94iGKl98TpZkf3B4dn7c6F5OgHi/wlYShs4F9lvP/wUjbRaJeC0++pThP+O
            7xmdVS/5eJ2VN1NGfoDNePKSnIlotcwkDgEy+XkhLFRViCdJw6k/qECpaw8PKnkJU4uZhbNk0pa9
            8EYyIQjAL6Ez6aSooGcO7VXS1T1ANupeAGrAGnUErFaDlvExgI2QLXlbCo/xVVdGT/fnjHVRrzss
            cY5IcEihufJJFsr6iecYRKop5ULOovkO9NUEZnKNEBFxhTSZjnWtoGcnn9hp3fLtH55Ii5SOHfkk
            1fBgAdiVZdixXN9ofg6AVJpKQlwvSJ4fgxPbFPyQhM5v70oSW9xjIWXFaGAg9b++9jq+pTloyUwJ
            NwhZNkFvOn13AI2wBiGGrg6SfknV7mP5tohPnw2A6GxmOwwTpU7WxiPXNSoomcPNry9WJk7uQpod
            e2DrDYKC9880o761mdxYRfdggRp2m3+3RQWUnmYBa2UjPF/7v0D9rwvslbFzA1xnXNS/L+aP5v/Q
            bVLes8K2yHsFpSywxVwdHO5qfP7MwwFxBx3DHDIzVTl+fIWMExu+wCFEkHpzrybUhsHysz1A2uNl
            fhjphPHPVQ4IyTYO6wj5AdgiWJ3MmXXq1gPcOUXnF5/HJBx0Sw==
            -----END CERTIFICATE-----
        tsaCerts:
          value: |
            -----BEGIN CERTIFICATE-----
            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
            5hpxbqCo8YLoRT5s1gLXCmeDBVrJpBA=
            -----END CERTIFICATE-----
  validationConfigurations:
    required: false
    verifyDigest: false
    mutateDigest: false
  validations:
    - expression: >-
        images.containers
        .filter(image, image.matches("(docker\\.io/)?devolutions/devolutions-server[:@].*"))
        .map(image, verifyImageSignatures(image, [attestors.notary]))
        .all(e, e > 0)
      message: "failed image signature verification"
```

### Images published before the switch to Notation

Tags released before Devolutions Server moved to Notation carry a cosign signature instead, and no Notation signature. Verify those with [cosign](https://docs.sigstore.dev/cosign/overview/) and the public key below:

```bash
cat > cosign.pub <<'EOF'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEuyxOC+3ZeSW8eUalDsYQJ7411UJJ
pvL+FPxCQzgP7XnvX8nuSqN9kgd2qhBOB547Dc75eIkZC0KPm3PRvmkbGQ==
-----END PUBLIC KEY-----
EOF

cosign verify --key cosign.pub devolutions/devolutions-server:<tag>
```

## Troubleshooting

### Pod not starting

Check the pod logs and events (adjust the `app` label and the `namespace` if you use overrides):

```bash
kubectl logs -l app=devolutions-server -n devolutions-server
kubectl describe pod -l app=devolutions-server -n devolutions-server
```

### Migration job failing

Not all upgrades trigger a database migration — they mostly occur on new major releases. When one does run, check the migration pod logs first:

```bash
kubectl logs -l component=db-migration -n devolutions-server
```

Failed migration jobs are kept for debugging and cleaned up on the next upgrade or by the TTL controller.

If you need to revert after a failed migration, restore the database from a snapshot taken before the upgrade **first**, then roll back to the previous image version. Rolling back the image without restoring the database will leave the schema in an inconsistent state.

### TLS certificate issues

Verify the certificate status:

```bash
kubectl get certificate
kubectl describe certificate <release>-tls
```
