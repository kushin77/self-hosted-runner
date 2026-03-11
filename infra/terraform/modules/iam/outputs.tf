/**
 * IAM Module - Outputs
 */

output "backend_service_account_email" {
  description = "Email of backend service account"
  value       = google_service_account.backend.email
}

output "frontend_service_account_email" {
  description = "Email of frontend service account"
  value       = google_service_account.frontend.email
}

output "terraform_service_account_email" {
  description = "Email of Terraform service account"
  value       = google_service_account.terraform.email
}

output "backend_service_account_name" {
  description = "Name of backend service account"
  value       = google_service_account.backend.account_id
}

output "frontend_service_account_name" {
  description = "Name of frontend service account"
  value       = google_service_account.frontend.account_id
}

output "terraform_service_account_name" {
  description = "Name of Terraform service account"
  value       = google_service_account.terraform.account_id
}

output "cloud_sql_proxy_role" {
  description = "Cloud SQL Proxy custom role"
  value       = google_project_iam_custom_role.cloud_sql_proxy.id
}

output "secret_reader_role" {
  description = "Secret Reader custom role"
  value       = google_project_iam_custom_role.secret_reader.id
}

output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID (if enabled)"
  value       = try(google_iam_workload_identity_pool.github[0].workload_identity_pool_id, null)
}

output "workload_identity_provider_id" {
  description = "Workload Identity Provider ID (if enabled)"
  value       = try(google_iam_workload_identity_pool_provider.github[0].workload_identity_pool_provider_id, null)
}
