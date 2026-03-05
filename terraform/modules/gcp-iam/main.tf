variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "sa_name" {
  description = "The name of the service account"
  type        = string
  default     = "vault-ops-sa"
}

resource "google_service_account" "vault_ops_sa" {
  account_id   = var.sa_name
  display_name = "Vault Ops Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "kms_access" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.vault_ops_sa.email}"
}

resource "google_project_iam_member" "storage_access" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.vault_ops_sa.email}"
}

resource "google_project_iam_member" "token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.vault_ops_sa.email}"
}

output "sa_email" {
  value = google_service_account.vault_ops_sa.email
}
