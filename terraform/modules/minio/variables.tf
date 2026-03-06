variable "docker_host" {
  description = "Docker daemon host (e.g., unix:///var/run/docker.sock or tcp://localhost:2375)"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "minio_root_user" {
  description = "MinIO root user (typically 'minioadmin')"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "MinIO root password (minimum 8 characters)"
  type        = string
  sensitive   = true
}

variable "minio_endpoint" {
  description = "MinIO HTTPS endpoint hostname (e.g., minio.internal.elevatediq.com)"
  type        = string
  default     = "minio.internal.elevatediq.com"
}

variable "minio_port" {
  description = "MinIO S3 API port (default 9000)"
  type        = number
  default     = 9000
}

variable "minio_console_port" {
  description = "MinIO Console UI port (default 9001)"
  type        = number
  default     = 9001
}

variable "minio_https_port" {
  description = "MinIO HTTPS port for external connections (default 9000)"
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
