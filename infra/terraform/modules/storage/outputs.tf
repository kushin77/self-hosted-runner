/**
 * Storage/GCS Module - Outputs
 */

output "terraform_state_bucket_name" {
  description = "Terraform state bucket name"
  value       = google_storage_bucket.terraform_state.name
}

output "terraform_state_bucket_url" {
  description = "Terraform state bucket URL"
  value       = "gs://${google_storage_bucket.terraform_state.name}"
}

output "artifacts_bucket_name" {
  description = "Container artifacts bucket name"
  value       = google_storage_bucket.artifacts.name
}

output "artifacts_bucket_url" {
  description = "Container artifacts bucket URL"
  value       = "gs://${google_storage_bucket.artifacts.name}"
}

output "backups_bucket_name" {
  description = "Database backups bucket name"
  value       = google_storage_bucket.backups.name
}

output "backups_bucket_url" {
  description = "Database backups bucket URL"
  value       = "gs://${google_storage_bucket.backups.name}"
}

output "audit_logs_bucket_name" {
  description = "Audit logs bucket name"
  value       = google_storage_bucket.audit_logs.name
}

output "audit_logs_bucket_url" {
  description = "Audit logs bucket URL"
  value       = "gs://${google_storage_bucket.audit_logs.name}"
}

output "kms_key_ring_id" {
  description = "KMS key ring ID"
  value       = google_kms_key_ring.storage.id
}

output "kms_crypto_key_id" {
  description = "KMS crypto key ID"
  value       = google_kms_crypto_key.storage.id
}
