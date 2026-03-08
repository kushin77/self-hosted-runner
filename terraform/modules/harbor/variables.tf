variable "namespace" {
  description = "Kubernetes namespace for Harbor deployment"
  type        = string
  default     = "harbor"
}

variable "hostname" {
  description = "Harbor external hostname (FQDN)"
  type        = string
}

variable "gcp_secret_project" {
  description = "GCP project containing Secret Manager secrets"
  type        = string
}

variable "admin_password_secret" {
  description = "GCP Secret Manager secret name for Harbor admin password"
  type        = string
  default     = "harbor-admin-password"
}

variable "database_password_secret" {
  description = "GCP Secret Manager secret name for Harbor database password"
  type        = string
  default     = "harbor-db-password"
}

variable "redis_password_secret" {
  description = "GCP Secret Manager secret name for Harbor Redis password"
  type        = string
  default     = "harbor-redis-password"
}

variable "storage_type" {
  description = "Storage backend type: gcs, s3, or azure"
  type        = string
  default     = "gcs"
  validation {
    condition     = contains(["gcs", "s3", "azure"], var.storage_type)
    error_message = "storage_type must be one of: gcs, s3, azure"
  }
}

variable "gcs_bucket" {
  description = "GCS bucket name for Harbor storage"
  type        = string
}

variable "enable_trivy" {
  description = "Enable Trivy vulnerability scanner"
  type        = bool
  default     = true
}

variable "trivy_skip_update" {
  description = "Skip Trivy vulnerability database update on startup"
  type        = bool
  default     = false
}

variable "harbor_chart_version" {
  description = "Harbor Helm chart version"
  type        = string
  default     = "1.14.0"
}

variable "harbor_image_tag" {
  description = "Harbor image tag (pinned for immutability)"
  type        = string
  default     = "v2.10.0"
}

variable "enable_smoke_test" {
  description = "Run smoke test job after deployment"
  type        = bool
  default     = true
}

variable "additional_helm_values" {
  description = "Additional Helm values (key-value map)"
  type        = map(string)
  default     = {}
}
