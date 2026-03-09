output "workload_identity_pool_id" {
  value = google_iam_workload_identity_pool.github_actions_pool.workload_identity_pool_id
}

output "workload_identity_provider_id" {
  value = google_iam_workload_identity_pool_provider.github_actions_provider.workload_identity_pool_provider_id
}

output "workload_identity_provider_name" {
  description = "Full resource name of the workload identity provider"
  value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_actions_provider.workload_identity_pool_provider_id}"
}
