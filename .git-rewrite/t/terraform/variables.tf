
// Root module variables are intentionally minimal. The gcp-vault module accepts
// its own inputs and is invoked from gcp-vault-infra.tf. If you need to override
// values, set them here and pass through to the module.

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

