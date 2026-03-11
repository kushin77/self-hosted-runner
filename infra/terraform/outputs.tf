/**
 * Terraform Outputs
 * Exported values for reference or cross-stack dependencies
 */

output "cloudrun_backend_url" {
  description = "NexusShield Portal Backend API URL"
  value       = "https://nexus-shield-portal-backend-REGION.a.run.app"
  sensitive   = false
}

output "cloudrun_frontend_url" {
  description = "NexusShield Portal Frontend URL"
  value       = "https://nexus-shield-portal-frontend-REGION.a.run.app"
  sensitive   = false
}

output "cloudsql_instance_name" {
  description = "CloudSQL instance name (for connections)"
  value       = "nexusshield-postgres-${var.environment}"
  sensitive   = false
}

output "cloudsql_host" {
  description = "CloudSQL public IP address (for remote connections)"
  value       = "CLOUDSQL_PUBLIC_IP"
  sensitive   = false
}

output "cloudsql_port" {
  description = "CloudSQL port"
  value       = 5432
  sensitive   = false
}

output "redis_host" {
  description = "Memorystore (Redis) host"
  value       = "REDIS_HOST"
  sensitive   = false
}

output "redis_port" {
  description = "Memorystore (Redis) port"
  value       = 6379
  sensitive   = false
}

output "service_account_email" {
  description = "Service account email for Cloud Run/Kubernetes"
  value       = "nexusshield-sa@GCP_PROJECT.iam.gserviceaccount.com"
  sensitive   = false
}

output "gcs_bucket_logs" {
  description = "GCS bucket for immutable logs"
  value       = "gs://nexusshield-logs-${var.environment}"
  sensitive   = false
}

output "terraform_state_bucket" {
  description = "GCS bucket storing Terraform state"
  value       = "gs://nexusshield-terraform-state"
  sensitive   = false
}
