variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "pool_id" {
  description = "Workload identity pool id"
  type        = string
  default     = "github-actions-pool"
}

variable "provider_id" {
  description = "Workload identity provider id"
  type        = string
  default     = "github-actions-provider"
}
