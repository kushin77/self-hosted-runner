output "minio_endpoint" {
  description = "MinIO service endpoint (in-cluster)"
  value       = "http://minio:9000"
  sensitive   = false
}

output "minio_console_endpoint" {
  description = "MinIO web console endpoint"
  value       = "http://minio:9001"
  sensitive   = false
}

output "minio_access_key_secret" {
  description = "GCP Secret Manager path to MinIO access key"
  value       = "projects/${var.gcp_secret_project}/secrets/${var.access_key_secret_name}"
  sensitive   = true
}

output "minio_secret_key_secret" {
  description = "GCP Secret Manager path to MinIO secret key"
  value       = "projects/${var.gcp_secret_project}/secrets/${var.secret_key_secret_name}"
  sensitive   = true
}

output "operator_release_name" {
  description = "Helm release name for MinIO Operator"
  value       = helm_release.minio_operator.name
}

output "tenant_release_name" {
  description = "Helm release name for MinIO Tenant"
  value       = helm_release.minio_tenant.name
}

output "namespace" {
  description = "Kubernetes namespace for MinIO deployment"
  value       = var.namespace
}

output "smoke_test_job_name" {
  description = "Smoke test job name (if enabled)"
  value       = var.enable_smoke_test ? kubernetes_job_v1.minio_smoke_test[0].metadata[0].name : null
}

output "deployment_status" {
  description = "Status of MinIO deployment"
  value = {
    operator_status = helm_release.minio_operator.status
    tenant_status   = helm_release.minio_tenant.status
  }
}
