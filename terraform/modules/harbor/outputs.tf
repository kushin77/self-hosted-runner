output "harbor_url" {
  description = "Harbor web UI URL"
  value       = "https://${var.hostname}"
  sensitive   = false
}

output "harbor_registry_url" {
  description = "Harbor Docker registry endpoint"
  value       = var.hostname
  sensitive   = false
}

output "harbor_admin_user" {
  description = "Harbor admin username"
  value       = "admin"
  sensitive   = false
}

output "harbor_admin_password_secret" {
  description = "GCP Secret Manager path to Harbor admin password"
  value       = "projects/${var.gcp_secret_project}/secrets/${var.admin_password_secret}"
  sensitive   = true
}

output "namespace" {
  description = "Kubernetes namespace for Harbor"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.harbor.name
}

output "deployment_status" {
  description = "Status of Harbor deployment"
  value       = helm_release.harbor.status
}

output "trivy_enabled" {
  description = "Whether Trivy scanner is enabled"
  value       = var.enable_trivy
}

output "storage_backend" {
  description = "Storage backend type"
  value       = var.storage_type
}

output "smoke_test_job_name" {
  description = "Smoke test job name (if enabled)"
  value       = var.enable_smoke_test ? kubernetes_job_v1.harbor_smoke_test[0].metadata[0].name : null
}
