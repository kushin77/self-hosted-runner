output "sa_email" {
  description = "The email of the created service account"
  value       = google_service_account.vault_ops_sa.email
}

output "sa_id" {
  description = "The unique ID of the created service account"
  value       = google_service_account.vault_ops_sa.unique_id
}
