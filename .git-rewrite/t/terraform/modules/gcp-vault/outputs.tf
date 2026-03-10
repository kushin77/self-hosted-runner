output "vault_kms_key_id" {
  value = google_kms_crypto_key.vault_unseal_key.id
}

output "vault_storage_bucket" {
  value = google_storage_bucket.vault_storage.name
}
output "vault_service_account_email" {
  value = google_service_account.vault_sa.email
}
