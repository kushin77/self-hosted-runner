# GCP Service Account for Vault Admin
# This account is used by Vault for GCS storage and KMS auto-unseal.

## Use the service account created inside the gcp_vault module

# Grant Storage Object Admin on the Vault bucket to the module-managed SA
resource "google_storage_bucket_iam_member" "vault_storage_admin" {
  bucket = module.gcp_vault.vault_storage_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.gcp_vault.vault_service_account_email}"
}

# Grant KMS Encrypter/Decrypter on the unseal key to the module-managed SA
resource "google_kms_crypto_key_iam_member" "vault_kms_unseal" {
  crypto_key_id = module.gcp_vault.vault_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${module.gcp_vault.vault_service_account_email}"
}

output "vault_service_account_email" {
  value       = module.gcp_vault.vault_service_account_email
  description = "The email of the vault admin service account (from module)"
}
