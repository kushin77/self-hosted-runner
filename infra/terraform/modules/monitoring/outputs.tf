/**
 * Cloud Monitoring Module - Outputs
 */

output "email_notification_channel_id" {
  description = "Email notification channel ID"
  value       = google_monitoring_notification_channel.email.id
}

output "slack_notification_channel_id" {
  description = "Slack notification channel ID"
  value       = try(google_monitoring_notification_channel.webhook[0].id, "")
}

output "infrastructure_dashboard_id" {
  description = "Infrastructure dashboard ID"
  value       = google_monitoring_dashboard.infrastructure.id
}

output "application_dashboard_id" {
  description = "Application dashboard ID"
  value       = google_monitoring_dashboard.application.id
}

output "alert_cloudsql_cpu_id" {
  description = "Cloud SQL CPU alert policy ID"
  value       = google_monitoring_alert_policy.cloudsql_cpu.id
}

output "alert_cloudsql_memory_id" {
  description = "Cloud SQL memory alert policy ID"
  value       = google_monitoring_alert_policy.cloudsql_memory.id
}

output "alert_redis_cpu_id" {
  description = "Redis CPU alert policy ID"
  value       = google_monitoring_alert_policy.redis_cpu.id
}

output "alert_redis_memory_id" {
  description = "Redis memory alert policy ID"
  value       = google_monitoring_alert_policy.redis_memory.id
}

output "alert_cloudrun_errors_id" {
  description = "Cloud Run error rate alert policy ID"
  value       = google_monitoring_alert_policy.cloudrun_errors.id
}

output "alert_cloudrun_latency_id" {
  description = "Cloud Run latency alert policy ID"
  value       = google_monitoring_alert_policy.cloudrun_latency.id
}
