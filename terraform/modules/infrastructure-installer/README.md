# All-in-One Infrastructure Installer (Data Plane Agent + Observability)

Single Terraform module that deploys the complete recommended infrastructure stack:
- MinIO (artifact storage)
- Harbor (container registry + scanning)
- Prometheus + Grafana (observability)
- AlertManager (alerting)
- Vault (secrets management)

**Use this for production deployments where you want immutable, repeatable infrastructure.**

## Quick Start

```hcl
module "infrastructure_stack" {
  source = "./terraform/modules/infrastructure-installer"

  gcp_project_id = "my-project"
  environment    = "production"
  region         = "us-central1"
  
  # Enable/disable components as needed
  enable_minio   = true
  enable_harbor  = true
  enable_observability = true
  enable_vault   = true
  
  # Credentials from GCP GSM (no hardcoding!)
  gsm_project_id = "my-security-project"
  
  # DNS/TLS
  base_domain    = "example.com"
  tls_issuer     = "letsencrypt-prod"  # cert-manager issuer
}

output "infrastructure" {
  value = {
    minio_endpoint    = module.infrastructure_stack.minio_endpoint
    harbor_url        = module.infrastructure_stack.harbor_url
    prometheus_url    = module.infrastructure_stack.prometheus_url
    grafana_url       = module.infrastructure_stack.grafana_url
  }
}
```

## What Gets Deployed

| Component | Purpose | HA | Scaling |
|-----------|---------|----|---------| 
| MinIO | S3-compatible object storage | Multi-replica | Manual |
| Harbor | Container registry + scanning | HA Postgres | Auto (HPA) |
| Prometheus | Metrics collection | N/A | PVC sized |
| Grafana | Dashboard/visualization | N/A | Stateless |
| AlertManager | Alert routing | N/A | Stateless |
| Vault | Secrets manager | HA storage | Manual |

## Features

### 1. Immutable Deployment
- All images pinned by digest
- Helm charts versioned and immutable
- Terraform state versioned in Git (encrypted)
- Deploy from commit SHA → reproducible infrastructure

### 2. Hands-Off Operations
- Single `terraform apply` deploys everything
- All credentials from GCP Secret Manager (rotated automatically)
- Health checks on all components
- Smoke tests validate deployment
- Auto-rollback on critical failures

### 3. Ephemeral Credentials
- No secrets in Git, Docker, or Terraform state
- All credentials stored in GCP Secret Manager
- 30-day rotation policy enforced
- Pod authentication via Workload Identity
- No hardcoded API keys

### 4. Cost Optimization
- Resource requests/limits set for cost tracking
- Spot instances where appropriate
- PVC auto-cleanup on 90-day idle
- Monitoring dashboard for spend
- Reserved capacity recommendations

## Files

- `main.tf` — Orchestrates sub-modules
- `minio.tf` — MinIO integration
- `harbor.tf` — Harbor integration  
- `observability.tf` — Prometheus/Grafana/AlertManager
- `vault.tf` — Vault integration
- `networking.tf` — Ingress, DNS, TLS setup
- `variables.tf` — Input variables (well-documented)
- `outputs.tf` — Output values for downstream tools
- `locals.tf` — Local computed values
- `tests/` — End-to-end smoke tests

## Deployment Example

### 1. Create Terraform backend (GCS)

```bash
# Create GCS bucket for state
gsutil mb gs://my-terraform-state/
gsutil versioning set on gs://my-terraform-state/

# Enable object versioning
gsutil versioning get gs://my-terraform-state/
```

### 2. Configure environment

```bash
# Create terraform.tfvars
cat > terraform.tfvars <<EOF
gcp_project_id = "my-project"
environment    = "production"
region         = "us-central1"
base_domain    = "example.com"

enable_minio   = true
enable_harbor  = true
enable_observability = true
enable_vault   = true

gsm_project_id = "my-security-project"
EOF
```

### 3. Initialize and apply

```bash
# Initialize Terraform
terraform init \
  -backend-config="bucket=my-terraform-state" \
  -backend-config="prefix=infrastructure/production"

# Validate configuration
terraform validate

# Generate and review plan
terraform plan -out=tfplan.binary

# Apply (after review)
terraform apply tfplan.binary
```

### 4. Verify deployment

```bash
# Check all resources
terraform show

# Get output endpoints
terraform output -json | jq '.[] | select(.sensitive == false)'

# Run smoke tests
bash terraform/modules/infrastructure-installer/tests/smoke-test-all.sh
```

## Adding Custom Components

To add additional services/modules:

1. Create new module in `terraform/modules/my-component/`
2. Add invocation in `infrastructure-installer/my-component.tf`
3. Add variables to support the new module
4. Add outputs
5. Test in staging first
6. Deploy to production

## Scaling & High Availability

### MinIO
- Horizontal: Add replicas via `var.minio_replicas` (max 10)
- Vertical: Increase storage via `var.minio_storage_capacity`
- HA: Uses Kubernetes StatefulSet replication

### Harbor
- Horizontal: `var.harbor_replicas` enables HPA
- Vertical: Database sizing via `var.harbor_db_instance_type`
- HA: External managed Postgres database

### Prometheus
- Retention: `var.prometheus_retention_days` (default 15)
- Storage: Configure `var.prometheus_storage_size`
- Scaling: Sidecar-based federation for multi-cluster

## Monitoring & Observability

All components export metrics visible in Grafana dashboards:

```bash
# Access Grafana
kubectl port-forward -n observability svc/grafana 3000:80
# User: admin
# Password: Get from GCP Secret Manager

gcloud secrets versions access latest --secret=grafana-admin-password
```

## Disaster Recovery

### Backup
```bash
# Automatic daily snapshots to GCS
terraform output -json | grep -i backup

# Manual backup
bash terraform/modules/infrastructure-installer/scripts/backup-all.sh
```

### Restore
```bash
# From GCS snapshot
bash terraform/modules/infrastructure-installer/scripts/restore-all.sh \
  --snapshot-date=2024-03-08 \
  --target-environment=disaster-recovery
```

## Cost Estimation

Before deployment, run:
```bash
terraform plan -out=tfplan.binary
terraform show tfplan.binary | grep -i "cost"

# More detailed: use Infracost
infracost breakdown --path tfplan.binary
```

## Security

- **Encryption**: All data encrypted at rest (GCS, PVC)
- **Network**: Private service endpoints, no public IPs
- **Access Control**: Workload Identity for pod auth
- **Secrets**: 100% GCP Secret Manager (never in Git)
- **Scanning**: Harbor Trivy scanning on all images
- **Audit**: All Terraform changes in Git audit trail

## Support & Troubleshooting

Detailed docs:
- `docs/INFRASTRUCTURE_INSTALLER_DEPLOYMENT.md` — Step-by-step guide
- `docs/INFRASTRUCTURE_INSTALLER_TROUBLESHOOTING.md` — Common issues
- `docs/INFRASTRUCTURE_INSTALLER_RUNBOOK.md` — Operational procedures

See parent issues:
- #515 (Data-plane agent epic)
- #523 (MinIO task)
- #527 (Harbor task)
- #544 (Vault task)

---

**Status:** Ready for Production Deployment ✅  
**Last Updated:** March 8, 2026  
**Tested:** All smoke tests passing on GKE 1.28+
