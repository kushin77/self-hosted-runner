output "kms_key_ring_id" {
  value = google_kms_key_ring.mirror.id
}

output "kms_crypto_key_id" {
  value = google_kms_crypto_key.mirror_key.id
}

output "wif_pool_id" {
  value = google_iam_workload_identity_pool.secrets_pool.workload_identity_pool_id
}

output "wif_provider_id" {
  value = google_iam_workload_identity_pool_provider.secrets_provider.name
}
