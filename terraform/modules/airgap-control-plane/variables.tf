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
