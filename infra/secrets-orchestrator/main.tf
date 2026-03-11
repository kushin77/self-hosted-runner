terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# KMS key ring and crypto key for secrets mirroring
resource "google_kms_key_ring" "mirror" {
  name     = var.kms_key_ring
  location = var.kms_location
}

resource "google_kms_crypto_key" "mirror_key" {
  name     = var.kms_key
  key_ring = google_kms_key_ring.mirror.id
}

# Workload Identity Pool + Provider for operator
resource "google_iam_workload_identity_pool" "secrets_pool" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "secrets-orchestrator-pool"
}

resource "google_iam_workload_identity_pool_provider" "secrets_provider" {
  workload_identity_pool_id                 = google_iam_workload_identity_pool.secrets_pool.workload_identity_pool_id
  workload_identity_pool_provider_id        = var.wif_provider_id
  display_name                              = "secrets-orchestrator-provider"
  oidc {
    issuer_uri = var.wif_issuer
  }
}
