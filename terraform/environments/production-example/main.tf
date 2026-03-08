# Example Usage: Infrastructure Installer

This directory contains production-ready examples for deploying the complete infrastructure stack.

## Quick Start

### 1. Production Environment (All Components)

```hcl
# terraform/environments/production/main.tf

terraform {
  backend "gcs" {
    bucket = "my-terraform-state"
    prefix = "infrastructure/production"
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

provider "kubernetes" {
  config_context = var.kubernetes_context
}

provider "helm" {
  kubernetes {
    config_context = var.kubernetes_context
  }
}

module "infrastructure" {
  source = "../../modules/infrastructure-installer"

  gcp_project_id  = var.gcp_project_id
  gsm_project_id  = var.gsm_project_id
  environment     = "production"
  region          = var.region
  base_domain     = var.base_domain

  # Enable all components
  enable_minio           = true
  enable_harbor          = true
  enable_observability   = true
  enable_vault           = true

  # Configuration
  minio_replicas              = 4
  minio_storage_capacity      = "500Gi"
  prometheus_retention_days   = 30
  prometheus_storage_size     = "100Gi"

  common_tags = {
    environment = "production"
    managed_by  = "terraform"
    team        = "platform"
  }
}

# Outputs for downstream tools
output "infrastructure" {
  value = {
    minio    = module.infrastructure.minio_endpoint
    harbor   = module.infrastructure.harbor_url
    grafana  = module.infrastructure.grafana_url
    vault    = module.infrastructure.vault_url
  }
}

output "secrets_paths" {
  value     = module.infrastructure.gcp_secret_manager_paths
  sensitive = true
}
```

### 2. Deploy

```bash
cd terraform/environments/production

# Initialize
terraform init \
  -backend-config="bucket=my-terraform-state" \
  -backend-config="prefix=infrastructure/production"

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Retrieve outputs
terraform output -json
```

### 3. Verify

```bash
# Check deployments
kubectl get all -n artifacts
kubectl get all -n harbor
kubectl get all -n observability

# Get endpoints
terraform output minio_endpoint
terraform output harbor_url
terraform output grafana_url
```

## Component-Only Deployments

### Just MinIO

```hcl
module "minio_only" {
  source = "../../modules/minio"
  
  namespace              = "artifacts"
  replicas              = 4
  storage_capacity      = "200Gi"
  gcp_secret_project    = var.gsm_project_id
  access_key_secret_name = "minio-access-key"
  secret_key_secret_name = "minio-secret-key"
}
```

### Just Harbor

```hcl
module "harbor_only" {
  source = "../../modules/harbor"

  namespace               = "harbor"
  hostname                = "harbor.example.com"
  gcp_secret_project      = var.gsm_project_id
  admin_password_secret   = "harbor-admin-password"
  database_password_secret = "harbor-db-password"
  redis_password_secret   = "harbor-redis-password"
  gcs_bucket              = "harbor-storage-prod"
  enable_trivy            = true
}
```

## Production Checklist

- [ ] GCP project created and configured
- [ ] GCS bucket for Terraform state (versioning enabled)
- [ ] GCP Secret Manager enabled with secrets pre-populated
- [ ] Kubernetes cluster running (GKE 1.28+)
- [ ] `gcloud` and `kubectl` CLI tools installed
- [ ] Terraform variables file created (`terraform.tfvars`)
- [ ] DNS domain delegated and available
- [ ] TLS certificates provisioned (cert-manager)

## Monitoring & Maintenance

### Health Checks

```bash
# Prometheus scrape targets
kubectl port-forward -n observability svc/prometheus 9090:9090
# Visit http://localhost:9090/targets

# Grafana dashboards
kubectl port-forward -n observability svc/grafana 3000:80
# Visit http://localhost:3000
# User: admin
# Password: $(gcloud secrets versions access latest --secret=grafana-admin-password)
```

### Backup & Restore

see `terraform/modules/infrastructure-installer/scripts/backup-all.sh`

### Scaling

To scale MinIO replicas:

```bash
terraform apply -var="minio_replicas=8"
```

To increase Prometheus retention:

```bash
terraform apply -var="prometheus_retention_days=60"
```

## Troubleshooting

### MinIO not accessible
```bash
kubectl logs -f -n artifacts deployment/minio
kubectl describe pvc -n artifacts
```

### Harbor pod crashes
```bash
kubectl logs -f -n harbor deployment/harbor-core
kubectl get events -n harbor --sort-by='.lastTimestamp'
```

### Prometheus not scraping
```bash
kubectl port-forward -n observability svc/prometheus 9090:9090
# Visit http://localhost:9090/targets (check scrape status)
```

## Support

See parent documentation:
- `docs/INFRASTRUCTURE_INSTALLER_DEPLOYMENT.md`
- `docs/INFRASTRUCTURE_INSTALLER_TROUBLESHOOTING.md`

Related GitHub issues:
- #515 - Data-plane agent epic
- #523 - MinIO task
- #527 - Harbor task
- #1384 - Terraform Ops Unblock (master)
