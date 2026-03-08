# Harbor Terraform Module - Production Ready

Production-grade Harbor deployment for container image scanning, Helm chart storage, and security policies.

## Quick Start

```hcl
module "harbor" {
  source = "./terraform/modules/harbor"

  namespace               = "harbor"
  hostname                = "harbor.example.com"
  admin_password_secret   = "harbor-admin-password"  # from GCP GSM
  database_password_secret = "harbor-db-password"     # from GCP GSM
  redis_password_secret   = "harbor-redis-password"   # from GCP GSM
  
  # External storage (GCS)
  storage_type           = "gcs"
  gcs_bucket             = "my-harbor-storage"
  
  # Trivy scanning enabled
  enable_trivy           = true
  trivy_skip_update      = false
  
  enable_smoke_test      = true
}
```

## Features

### 1. Immutable Scanning Platform
- Trivy vulnerability scanner (auto-enabled)
- Clair integration for deep scanning
- Digest-pinned images for reproducibility
- Automated policy enforcement

### 2. Ephemeral Secrets Management
- All credentials stored in GCP Secret Manager
- Automatic credential rotation (30-day policy)
- No hardcoded passwords
- Workload Identity for pod auth

### 3. Hands-Off Operations
- Helm deployment (fully idempotent)
- Pre-upgrade backups (GCS)
- Health checks on deployment
- Auto-rollback on failure
- Smoke test job validates deployment

### 4. Storage Optimization
- GCS backend for chart/image storage
- Compression enabled
- Lifecycle policies (auto-delete old versions)
- Cost monitoring

### 5. Chart Repository Integration
- ChartMuseum support (optional)
- Chart scanning for vulnerabilities
- Index auto-updates

## Files

- `main.tf` — Core Harbor deployment
- `helm.tf` — Helm configuration
- `gcp_gsm.tf` — GCP Secret Manager integration
- `gcs_backend.tf` — Google Cloud Storage backend
- `trivy_scanner.tf` — Trivy scanner configuration
- `variables.tf` — Input variables
- `outputs.tf` — Output values
- `tests/` — Smoke tests and integration tests

## Deployment

```bash
cd terraform/environments/production
terraform apply -target=module.harbor
```

## Smoke Testing

Automatic test on deployment:
```bash
kubectl logs -f -n harbor job/harbor-smoke-test
```

## Monitoring & Alerts

Harbor exports Prometheus metrics:
```bash
kubectl port-forward -n harbor svc/harbor 8001:80
curl http://localhost:8001/api/v2.0/systeminfo
```

## See Also

- [Harbor Helm chart (deploy/harbor)](../../deploy/harbor/README.md)
- [Trivy documentation](https://aquasecurity.github.io/trivy/)
- [ChartMuseum docs](https://chartmuseum.com/)
- Issue #527, #590 (parent epics)
