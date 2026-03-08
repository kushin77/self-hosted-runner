variable "gcp_project_id" {
  description = "GCP project ID for infrastructure"
  type        = string
}

variable "gsm_project_id" {
  description = "GCP project ID containing Secret Manager (can differ from gcp_project_id)"
  type        = string
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "environment must be one of: production, staging, development"
  }
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "base_domain" {
  description = "Base domain for infrastructure (e.g., example.com)"
  type        = string
}

# Component toggles
variable "enable_minio" {
  description = "Deploy MinIO for artifact storage"
  type        = bool
  default     = true
}

variable "enable_harbor" {
  description = "Deploy Harbor for container registry"
  type        = bool
  default     = true
}

variable "enable_observability" {
  description = "Deploy Prometheus, Grafana, AlertManager"
  type        = bool
  default     = true
}

variable "enable_vault" {
  description = "Deploy Vault for secrets management"
  type        = bool
  default     = false
}

# MinIO configuration
variable "minio_replicas" {
  description = "Number of MinIO replicas"
  type        = number
  default     = 4
  validation {
    condition     = var.minio_replicas >= 1 && var.minio_replicas <= 10
    error_message = "minio_replicas must be between 1 and 10"
  }
}

variable "minio_storage_capacity" {
  description = "Storage capacity per MinIO instance"
  type        = string
  default     = "100Gi"
}

variable "minio_storage_class" {
  description = "Kubernetes storage class for MinIO"
  type        = string
  default     = "standard-rwo"
}

variable "minio_image_tag" {
  description = "MinIO server image tag (pinned for immutability)"
  type        = string
  default     = "RELEASE.2024-03-07T00-43-48Z"
}

# Harbor configuration
variable "harbor_replicas" {
  description = "Number of Harbor core replicas"
  type        = number
  default     = 2
}

variable "harbor_image_tag" {
  description = "Harbor image tag (pinned for immutability)"
  type        = string
  default     = "v2.10.0"
}

# Observability configuration
variable "prometheus_retention_days" {
  description = "Prometheus metrics retention in days"
  type        = number
  default     = 15
}

variable "prometheus_storage_size" {
  description = "Prometheus PVC storage size"
  type        = string
  default     = "50Gi"
}

# Networking
variable "nginx_ingress_chart_version" {
  description = "nginx-ingress Helm chart version"
  type        = string
  default     = "4.10.0"
}

variable "tls_issuer" {
  description = "cert-manager issuer name (e.g., letsencrypt-prod)"
  type        = string
  default     = "letsencrypt-prod"
}

# Helm overrides
variable "additional_helm_values" {
  description = "Additional Helm values overrides (map of string -> string)"
  type        = map(string)
  default     = {}
}

# Tags and labels
variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    stack      = "infrastructure-installer"
    version    = "1.0"
  }
}
