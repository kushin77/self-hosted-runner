terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "phase0.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# KMS Key Ring
resource "google_kms_key_ring" "nexus" {
  name     = "nexus-keyring"
  location = var.region
}

# KMS Crypto Key
resource "google_kms_crypto_key" "nexus" {
  name            = "nexus-key"
  key_ring        = google_kms_key_ring.nexus.id
  rotation_period = "7776000s" # 90 days
}

# Google Secret Manager - for storing secrets encrypted with KMS
resource "google_secret_manager_secret" "nexus_secrets" {
  secret_id = "nexus-secrets"
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# Give Cloud Build SA access to decrypt with KMS
resource "google_kms_crypto_key_iam_member" "cloudbuild_kms" {
  crypto_key_id = google_kms_crypto_key.nexus.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
}

# Give Cloud Build SA access to read secrets from GSM
resource "google_secret_manager_secret_iam_member" "cloudbuild_secret" {
  secret_id = google_secret_manager_secret.nexus_secrets.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
}

# Basic Cloud Build trigger for the repository
resource "google_cloudbuild_trigger" "nexus_main" {
  count    = var.github_owner != "" && var.github_repo != "" ? 1 : 0
  name     = "nexus-deploy-main"
  filename = "cloudbuild.yaml"
  
  github {
    owner  = var.github_owner
    name   = var.github_repo
    
    push {
      branch = "^main$"
    }
  }
  
  description = "Phase0 Nexus deployment trigger"
  
  depends_on = [
    google_kms_crypto_key_iam_member.cloudbuild_kms,
    google_secret_manager_secret_iam_member.cloudbuild_secret
  ]
}

# Outputs
output "kms_key_id" {
  value       = google_kms_crypto_key.nexus.id
  description = "KMS Key ID for encryption"
}

output "gsm_secret_id" {
  value       = google_secret_manager_secret.nexus_secrets.id
  description = "Google Secret Manager secret ID"
}

output "cloudbuild_trigger_id" {
  value       = try(google_cloudbuild_trigger.nexus_main[0].id, null)
  description = "Cloud Build trigger ID"
}
