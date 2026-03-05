# GCP Infrastructure for Vault High Availability
# This module provisions the KMS key for auto-unseal and GCS bucket for storage.

// Root module: delegate GCP Vault infra to the gcp-vault child module.
// Configure `project_id`, `region`, and `bucket_prefix` in `variables.tf`.

module "gcp_vault" {
  source        = "./modules/gcp-vault"
  project_id    = var.project_id
  region        = var.region
  bucket_prefix = var.bucket_prefix
  github_repo   = var.github_repo
}
