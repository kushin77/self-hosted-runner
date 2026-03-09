variable "namespace" {
  description = "Kubernetes namespace to install KEDA and metrics adapter into"
  type        = string
  default     = "keda"
}

variable "keda_version" {
  description = "Helm chart version for KEDA"
  type        = string
  default     = "2.11.0"
}

variable "prometheus_adapter_version" {
  description = "Helm chart version for Prometheus Adapter"
  type        = string
  default     = "2.21.0"
}
