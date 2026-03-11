output "kms_key_ring_id" {
  description = "Reference to existing KMS key ring"
  value       = "projects/${var.project_id}/locations/${var.kms_location}/keyRings/${var.kms_key_ring}"
}

output "kms_crypto_key_id" {
  description = "Reference to existing KMS crypto key (import via terraform import)"
  value       = "projects/${var.project_id}/locations/${var.kms_location}/keyRings/${var.kms_key_ring}/cryptoKeys/${var.kms_key}"
}

output "wif_pool_id" {
  description = "ID of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.secrets_pool.workload_identity_pool_id
}

output "wif_provider_reference" {
  description = "Reference to WIF provider (import via terraform import)"
  value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/${var.wif_pool_id}/providers/${var.wif_provider_id}"
}
