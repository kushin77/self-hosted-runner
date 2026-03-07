variable "namespace_name" {
  type    = string
  default = "airgap-control-plane"
}

variable "namespace_labels" {
  type    = map(string)
  default = {}
}

variable "allowed_registry_cidr" {
  type        = string
  description = "CIDR for allowed image registry egress (e.g., 10.0.0.0/24)"
  default     = "0.0.0.0/0"
}

variable "allowed_collector_cidr" {
  type        = string
  description = "CIDR for allowed OTEL collector egress (e.g., 10.0.1.0/24)"
  default     = "0.0.0.0/0"
}

variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster"
}

variable "namespace" {
  type        = string
  description = "Namespace for RunnerCloud components"
  default     = "runnercloud"
}

# Helm Release Configuration
variable "helm_release_name" {
  type        = string
  description = "Name of the Helm release"
  default     = "airgap-control-plane"
}

variable "helm_repository" {
  type        = string
  description = "Helm repository URL for air-gap control plane chart"
  default     = ""
}

variable "helm_chart_name" {
  type        = string
  description = "Name of the Helm chart"
  default     = "airgap-control-plane"
}

variable "helm_chart_version" {
  type        = string
  description = "Version of the Helm chart"
  default     = "1.0.0"
}

# Image Preload Configuration
variable "image_loader_image" {
  type        = string
  description = "Container image for the image loader job"
  default     = "alpine:latest"
}

variable "image_loader_pvc" {
  type        = string
  description = "PVC name for storing image tarballs"
  default     = "image-storage-pvc"
}

variable "image_pull_secrets_enabled" {
  type        = bool
  description = "Whether to enable image pull secrets"
  default     = false
}

variable "create_image_storage_pvc" {
  type        = bool
  description = "Whether to create a PVC for image storage"
  default     = true
}

variable "image_storage_size" {
  type        = string
  description = "Size of the image storage PVC"
  default     = "50Gi"
}

variable "storage_class_name" {
  type        = string
  description = "Storage class name for image storage PVC"
  default     = "standard"
}

# Collector Configuration
variable "collector_enabled" {
  type        = bool
  description = "Whether to enable OTEL collector deployment"
  default     = true
}

variable "collector_image" {
  type        = string
  description = "Container image for OTEL collector"
  default     = "otel/opentelemetry-collector-k8s:latest"
}

variable "collector_endpoint" {
  type        = string
  description = "OTEL collector endpoint"
  default     = ""
}

# Registry Mirror Configuration
variable "registry_mirror_enabled" {
  type        = bool
  description = "Whether to enable offline registry mirror configuration"
  default     = true
}

variable "registry_mirror_url" {
  type        = string
  description = "URL of the offline registry mirror (e.g., harbor.example.com)"
  default     = ""
}

variable "registry_auth_enabled" {
  type        = bool
  description = "Whether registry authentication is required"
  default     = false
}

variable "registry_username" {
  type        = string
  description = "Username for registry authentication"
  sensitive   = true
  default     = ""
}

variable "registry_password" {
  type        = string
  description = "Password for registry authentication"
  sensitive   = true
  default     = ""
}
