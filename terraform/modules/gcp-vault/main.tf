# GCP Vault infra module: KMS, GCS, Workload Identity

resource "google_storage_bucket" "vault_storage" {
  project       = var.project_id
  name          = "${var.bucket_prefix}-${var.project_id}"
  location      = var.region
  force_destroy = false
  storage_class = "STANDARD"

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.vault_unseal_key.id
  }
}

resource "google_kms_key_ring" "vault_key_ring" {
  project  = var.project_id
  name     = "vault-unseal-ring"
  location = var.region
}

resource "google_kms_crypto_key" "vault_unseal_key" {
  name     = "vault-unseal-key"
  key_ring = google_kms_key_ring.vault_key_ring.id
  purpose  = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "vault_sa" {
  project      = var.project_id
  account_id   = "vault-admin-sa"
  display_name = "Vault Admin Service Account"
}
// Workload Identity Pool & Provider are intentionally NOT created here due to
// provider schema differences across google provider versions. Create a
// Workload Identity Pool/Provider and bind it to the `vault-admin-sa` manually
// or with a separately-tested Terraform module. See docs/TODO_INFRA_ISSUES.md
// for the recommended steps and commands.

resource "google_kms_crypto_key_iam_member" "vault_kms_access" {
  crypto_key_id = google_kms_crypto_key.vault_unseal_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.vault_sa.email}"
}

resource "google_storage_bucket_iam_member" "vault_storage_access" {
  bucket = google_storage_bucket.vault_storage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vault_sa.email}"
}
