/**
 * Cloud Logging Module - Outputs
 */

output "audit_logs_bucket_name" {
  description = "Audit logs bucket name"
  value       = google_logging_project_bucket_config.audit_logs.bucket_id
}

output "application_logs_bucket_name" {
  description = "Application logs bucket name"
  value       = google_logging_project_bucket_config.application_logs.bucket_id
}

output "cloudrun_logs_sink_name" {
  description = "Cloud Run logs sink name"
  value       = google_logging_project_sink.cloudrun_logs.name
}

output "cloudsql_logs_sink_name" {
  description = "Cloud SQL logs sink name"
  value       = google_logging_project_sink.cloudsql_logs.name
}

output "audit_logs_sink_name" {
  description = "Audit logs sink name"
  value       = google_logging_project_sink.audit_logs_sink.name
}

output "vpc_flow_logs_sink_name" {
  description = "VPC flow logs sink name"
  value       = google_logging_project_sink.vpc_flow_logs.name
}

output "redis_logs_sink_name" {
  description = "Redis logs sink name"
  value       = google_logging_project_sink.redis_logs.name
}

output "error_count_metric_name" {
  description = "Error count metric name"
  value       = google_logging_metric.error_count.name
}

output "error_rate_metric_name" {
  description = "Error rate metric name"
  value       = google_logging_metric.error_rate.name
}

output "latency_p99_metric_name" {
  description = "P99 latency metric name"
  value       = google_logging_metric.latency_p99.name
}
