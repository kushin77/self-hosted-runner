
// Root module variables are intentionally minimal. The gcp-vault module accepts
// its own inputs and is invoked from gcp-vault-infra.tf. If you need to override
// values, set them here and pass through to the module.

variable "project_id" {
  description = "GCP project id to create Vault infra in"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "bucket_prefix" {
  description = "Prefix for GCS bucket names to avoid collisions"
  type        = string
  default     = "vault-data"
}

# MinIO Artifact Storage Variables
variable "docker_host" {
  description = "Docker daemon host for MinIO deployment"
  type        = string
  default     = ""  # Uses default unix socket if empty
}

variable "minio_root_user" {
  description = "MinIO root user"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "MinIO root password (minimum 8 characters)"
  type        = string
  sensitive   = true
  default     = "minioadmin"  # Override in tfvars or via environment
}

variable "minio_endpoint" {
  description = "MinIO HTTPS endpoint hostname"
  type        = string
  default     = "minio.internal.elevatediq.com"
}

variable "minio_port" {
  description = "MinIO S3 API port"
  type        = number
  default     = 9000
}

variable "minio_console_port" {
  description = "MinIO Console UI port"
  type        = number
  default     = 9001
}

variable "minio_https_port" {
  description = "MinIO HTTPS external port"
  type        = number
  default     = 9000
}

variable "minio_bucket_name" {
  description = "S3 bucket name for GitHub Actions artifacts"
  type        = string
  default     = "github-actions-artifacts"
}

variable "minio_data_path" {
  description = "Host path for MinIO data persistence"
  type        = string
  default     = "/data/minio"
}

