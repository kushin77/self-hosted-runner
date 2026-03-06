variable "namespace" {
  description = "Kubernetes namespace to deploy MinIO into"
  type        = string
  default     = "minio"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "minio"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig for Helm provider"
  type        = string
  default     = "~/.kube/config"
}
