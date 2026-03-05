variable "project_id" {
  description = "GCP project id to create Vault infra in"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "bucket_prefix" {
  description = "Prefix for GCS bucket names to avoid collisions"
  type        = string
  default     = "vault-data"
}

variable "github_repo" {
  description = "GitHub repository full name (owner/repo) used for Workload Identity binding"
  type        = string
  default     = "akushnir/self-hosted-runner"
}
