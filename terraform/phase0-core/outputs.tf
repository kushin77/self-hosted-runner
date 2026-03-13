output "kms_key_ring_name" {
  value = google_kms_key_ring.nexus_keyring.name
}

output "kms_crypto_key_name" {
  value = google_kms_crypto_key.nexus_key.name
}

output "secret_name" {
  value = google_secret_manager_secret.app_secret.secret_id
}

output "cloudbuild_trigger_id" {
  value = length(google_cloudbuild_trigger.nexus_deploy) > 0 ? google_cloudbuild_trigger.nexus_deploy[0].id : ""
}
