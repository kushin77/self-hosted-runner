variable "namespace" {
  description = "Kubernetes namespace for MinIO deployment"
  type        = string
  default     = "artifacts"
}

variable "replicas" {
  description = "Number of MinIO replicas (servers)"
  type        = number
  default     = 4
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10
    error_message = "Replicas must be between 1 and 10"
  }
}

variable "storage_capacity" {
  description = "Storage capacity per MinIO instance (K8s format, e.g., 100Gi)"
  type        = string
  default     = "100Gi"
}

variable "storage_class" {
  description = "Kubernetes storage class for PVC"
  type        = string
  default     = "standard-rwo"
}

variable "tls_enabled" {
  description = "Enable TLS for MinIO communication"
  type        = bool
  default     = true
}

variable "tls_cert_secret_name" {
  description = "Kubernetes secret name containing TLS cert and key"
  type        = string
  default     = "minio-certs"
}

variable "gcp_secret_project" {
  description = "GCP project containing Secret Manager secrets"
  type        = string
}

variable "access_key_secret_name" {
  description = "GCP Secret Manager secret name for MinIO access key"
  type        = string
  default     = "minio-access-key"
}

variable "secret_key_secret_name" {
  description = "GCP Secret Manager secret name for MinIO secret key"
  type        = string
  default     = "minio-secret-key"
}

variable "operator_image_tag" {
  description = "MinIO Operator image tag (pinned for immutability)"
  type        = string
  default     = "v5.0.14"
}

variable "operator_chart_version" {
  description = "MinIO Operator Helm chart version"
  type        = string
  default     = "5.0.14"
}

variable "minio_image_tag" {
  description = "MinIO server image tag (pinned for immutability)"
  type        = string
  default     = "RELEASE.2024-03-07T00-43-48Z"
}

variable "minio_chart_version" {
  description = "MinIO Tenant Helm chart version"
  type        = string
  default     = "5.0.0"
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
