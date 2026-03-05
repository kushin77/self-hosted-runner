variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster"
}

variable "namespace" {
  type        = string
  description = "Namespace for RunnerCloud components"
  default     = "runnercloud"
}
