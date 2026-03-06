output "endpoint" {
  description = "MinIO S3 API endpoint URL"
  value       = "https://${var.minio_endpoint}:${var.minio_https_port}"
}

output "bucket_name" {
  description = "GitHub Actions artifacts bucket name"
  value       = var.minio_bucket_name
}

output "region" {
  description = "AWS region (always us-east-1 for MinIO)"
  value       = "us-east-1"
}

output "access_key" {
  description = "MinIO root access key"
  value       = var.minio_root_user
}

output "secret_key" {
  description = "MinIO root secret key (sensitive)"
  value       = var.minio_root_password
  sensitive   = true
}

output "console_url" {
  description = "MinIO Console UI URL"
  value       = "http://${var.minio_endpoint}:${var.minio_console_port}"
}

output "container_id" {
  description = "Docker container ID for MinIO"
  value       = docker_container.minio.id
}

output "network_id" {
  description = "Docker network ID for MinIO"
  value       = docker_network.minio_net.id
}
