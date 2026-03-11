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

# KMS resources - import existing or create new
# To import existing resources:
#   terraform import google_kms_crypto_key.mirror_key projects/nexusshield-prod/locations/global/keyRings/nexusshield/cryptoKeys/mirror-key
# For now, we skip creation and rely on manual provisioning or data sources

# Workload Identity Pool (create new or reference existing)
resource "google_iam_workload_identity_pool" "secrets_pool" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "secrets-orchestrator-pool"
  description               = "Pool for operator-driven secret orchestration"
  # Note: If this pool already exists, this will error; comment out and use data source instead
  lifecycle {
    ignore_changes = [description, display_name]
  }
}

# References only - skip creation for now
# These resources are managed separately outside Terraform
# To re-enable: run 'terraform import' for the full resource names
