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
| **Stable** | `2025.3.15` | No | Production-ready releases |
| **LTS** | `2025.3.15` | No | Long-term support releases |
| **Beta** | `2026.1.3-beta` | Yes | Pre-release versions for early testing |

By default, `helm install` and `helm search` only show Stable and LTS versions. To include Beta releases, add the `--devel` flag:

```bash
# Search for all versions including beta
helm search repo devolutions/devolutions-server --devel

# Install a specific beta version
helm install dvls devolutions/devolutions-server --version 2026.1.3-beta
```

### Create the required secrets

The chart expects two Kubernetes secrets to exist before installation. Create them using your preferred method (Terraform, Vault, sealed-secrets, etc.). The `kubectl` examples below are for illustration only.

**Docker Hub registry credentials** (referenced by `imagePullSecrets`):

```bash
kubectl create secret docker-registry docker-hub \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username='<username>' \
  --docker-password='<password>'
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
  tag: '2025.3.15.0'

imagePullSecrets:
  - name: docker-hub

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
| `migration.kubectl.image` | kubectl image for scale-down job | `bitnami/kubectl` |
| `migration.kubectl.tag` | kubectl image tag — defaults to `latest`; pin to a specific version compatible with your cluster (current Kubernetes version or n-1) when possible | `latest` |
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
