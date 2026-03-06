# Main MinIO deployment using the minio module
# This file configures MinIO artifact storage for GitHub Actions

module "minio" {
  source = "./modules/minio"

  docker_host = var.docker_host != "" ? var.docker_host : "unix:///var/run/docker.sock"

  minio_root_user     = var.minio_root_user
  minio_root_password = var.minio_root_password
  minio_endpoint      = var.minio_endpoint
  minio_port          = var.minio_port
  minio_console_port  = var.minio_console_port
  minio_https_port    = var.minio_https_port
  minio_bucket_name   = var.minio_bucket_name
  minio_data_path     = var.minio_data_path
}

# Output MinIO connection details for use in CI/CD
output "minio_endpoint" {
  description = "MinIO S3 API endpoint for GitHub Actions secrets"
  value       = module.minio.endpoint
}

output "minio_bucket" {
  description = "S3 bucket name for artifacts"
  value       = module.minio.bucket_name
}

output "minio_access_key" {
  description = "MinIO access key (root user)"
  value       = module.minio.access_key
}

output "minio_secret_key" {
  description = "MinIO secret key (sensitive, not for logs)"
  value       = module.minio.secret_key
  sensitive   = true
}

output "minio_console_url" {
  description = "MinIO Console UI for manual access"
  value       = module.minio.console_url
}
