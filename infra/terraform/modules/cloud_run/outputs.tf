/**
 * Cloud Run Module - Outputs
 */

output "backend_service_name" {
  description = "Backend Cloud Run service name"
  value       = google_cloud_run_service.backend.name
}

output "backend_service_url" {
  description = "Backend Cloud Run service URL"
  value       = google_cloud_run_service.backend.status[0].url
}

output "backend_revision" {
  description = "Backend Cloud Run latest revision"
  value       = google_cloud_run_service.backend.status[0].latest_created_revision_name
}

output "frontend_service_name" {
  description = "Frontend Cloud Run service name"
  value       = google_cloud_run_service.frontend.name
}

output "frontend_service_url" {
  description = "Frontend Cloud Run service URL"
  value       = google_cloud_run_service.frontend.status[0].url
}

output "frontend_revision" {
  description = "Frontend Cloud Run latest revision"
  value       = google_cloud_run_service.frontend.status[0].latest_created_revision_name
}

output "backend_ingress_settings" {
  description = "Backend ingress settings"
  value       = google_cloud_run_service.backend.status[0].conditions[0].message
}

output "frontend_ingress_settings" {
  description = "Frontend ingress settings"
  value       = google_cloud_run_service.frontend.status[0].conditions[0].message
}
