# MinIO Terraform Module - Production Ready

This module provisions a production-grade MinIO deployment for artifact storage with:
- High availability (replica set)
- GCP GSM secret integration (no hardcoded credentials)
- TLS/mTLS support
- Helm-based deployment
- Smoke testing via job

## Quick Start

```hcl
module "minio" {
  source = "./terraform/modules/minio"

  namespace             = "artifacts"
  replicas              = 4
  storage_capacity      = "100Gi"
  storage_class         = "standard-rwo"
  tls_enabled           = true
  tls_cert_secret_name  = "minio-certs"
  
  # Credentials from GCP GSM (ephemeral)
  gcp_secret_project = "my-project"
  access_key_secret_name = "minio-access-key"      # stored in GSM
  secret_key_secret_name = "minio-secret-key"      # stored in GSM
  
  enable_smoke_test = true
}
```

## Features

### 1. Immutable Images
- MinIO official images (versioned)
- Digest pinning for repeatability
- Image scanning via Harbor integration

### 2. Ephemeral Credentials
- Credentials stored in GCP Secret Manager
- Rotated automatically every 30 days
- No credentials in Git or Terraform state
- Uses Workload Identity for pod authentication

### 3. Hands-Off Automation
- Helm deployment (idempotent)
- Automatic backup creation pre-upgrade
- Health checks on deployment
- Auto-rollback on failure

### 4. Storage Optimization
- Multi-tier storage (SSD for hot, standard for archive)
- Configurable tiering policies
- Cost monitoring dashboard

## Files

- `main.tf` — Core MinIO deployment module
- `helm.tf` — Helm chart configuration
- `gcp_gsm.tf` — GCP Secret Manager integration
-` variables.tf` — Input variables (documented)
- `outputs.tf` — Output values (endpoints, credentials paths)
- `locals.tf` — Local values for computed attributes
- `tests/` — Smoke test job definitions

## Deployment

```bash
cd terraform/environments/production
terraform apply -target=module.minio
```

## Smoke Testing

Automatic smoke test on deployment:
```bash
kubectl logs -f -n artifacts job/minio-smoke-test
```

Manual test:
```bash
bash terraform/modules/minio/tests/smoke-test.sh
```

## See Also

- [Helm chart in deploy/minio](../../deploy/minio/README.md)
- [MinIO Operator docs](https://min.io/docs/minio/kubernetes/upstream/)
- Issue #523 (parent epic)
