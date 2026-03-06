# MinIO Artifact Storage Module

Provides idempotent, sovereign MinIO S3-compatible artifact storage for GitHub Actions.

## Features

- **Immutable**: All configuration via Terraform
- **Sovereign**: Self-hosted, no external dependencies
- **Ephemeral**: Artifacts are temporary, not persistent
- **Independent**: Works without external services

## Usage

```hcl
module "minio" {
  source = "./modules/minio"
  
  minio_root_user     = var.minio_root_user     # e.g., "minioadmin"
  minio_root_password = var.minio_root_password
  minio_endpoint      = var.minio_endpoint      # e.g., "minio.internal.elevatediq.com"
  minio_port          = var.minio_port          # e.g., 9000
  minio_bucket_name   = var.minio_bucket_name   # e.g., "github-actions-artifacts"
  
  environment_tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

## Outputs

- `endpoint` — MinIO S3 API endpoint
- `bucket_name` — Artifact bucket name
- `region` — AWS region (always "us-east-1" for MinIO)
- `access_key` — Root access key
- `secret_key` — Root secret key (marked sensitive)

## Requirements

- Docker or Kubernetes with MinIO deployment
- Network access on port 9000 (S3 API)
- Volume mount for persistent data (or ephemeral for testing)

## Security

- Root credentials stored in Terraform state (use remote backend)
- Service account credentials managed separately in GitHub Secrets
- All communications over TLS (requires certificate)
