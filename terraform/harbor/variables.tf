variable "namespace" {
  description = "Kubernetes namespace to deploy Harbor into"
  type        = string
  default     = "harbor"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "harbor"
}
