terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_kms_key_ring" "nexus_keyring" {
  name     = "nexus-keyring"
  location = var.kms_location
  project  = var.project_id
}

resource "google_kms_crypto_key" "nexus_key" {
  name     = "nexus-crypto-key"
  key_ring = google_kms_key_ring.nexus_keyring.id
  project  = var.project_id
  rotation_period = "7776000s" # 90 days
}

resource "google_secret_manager_secret" "app_secret" {
  secret_id = var.secret_id
  project   = var.project_id
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "app_secret_version" {
  secret      = google_secret_manager_secret.app_secret.id
  secret_data = var.secret_data
  depends_on  = [google_secret_manager_secret.app_secret]
}

resource "google_secret_manager_secret_iam_member" "cb_sa_accessor" {
  secret_id = google_secret_manager_secret.app_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.cloud_build_service_account}"
}

resource "google_kms_crypto_key_iam_member" "cb_kms_role" {
  crypto_key_id = google_kms_crypto_key.nexus_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.cloud_build_service_account}"
}

# Sample Cloud Build trigger (requires Cloud Build GitHub App / repo connection to be configured)
resource "google_cloudbuild_trigger" "nexus_deploy" {
  count = length(trim(var.github_owner)) > 0 && length(trim(var.github_repo)) > 0 ? 1 : 0

  name = "nexus-deploy-trigger"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = var.github_branch
    }
  }

  filename = "cloudbuild.yaml"
}
