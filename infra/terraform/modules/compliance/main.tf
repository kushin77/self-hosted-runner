/**
 * Compliance Module - Main
 * Implements basic compliance checks via IAM bindings and policy checks.
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# IAM policy viewer binding for audit accounts
resource "google_project_iam_member" "audit_viewer" {
  project = var.project_id
  role    = "roles/browser"
  member  = "group:cloud-audit@${var.project_id}.iam.gserviceaccount.com"
}

# Ensure buckets are encrypted and have logging enabled (sample check using conditional)
# Note: This module does not enforce, but reports via outputs for validation scripts

data "google_storage_bucket" "terraform_state" {
  project = var.project_id
  name    = "${var.service_name}-terraform-state-${var.environment}-${data.google_client_config.current.project}"
}

# KMS check
data "google_kms_crypto_key" "storage_key" {
  project  = var.project_id
  location = data.google_client_config.current.region
  name     = "${var.service_name}-storage-key-${var.environment}"
  key_ring = "${var.service_name}-storage-keyring-${var.environment}"
}

# Outputs for scripts to assert compliance
output "terraform_state_bucket_encryption" {
  value = try(data.google_storage_bucket.terraform_state.encryption.default_kms_key_name, "")
}

output "kms_key_present" {
  value = try(data.google_kms_crypto_key.storage_key.id, "")
}

# Data sources
data "google_client_config" "current" {}
