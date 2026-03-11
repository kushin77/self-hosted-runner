/**
 * Cloud Monitoring Module - Dashboards, Alert Policies, Notification Channels
 * Provides comprehensive monitoring for GCP infrastructure
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "service_name" {
  description = "Service name prefix"
  type        = string
  default     = "nexus-shield"
}

variable "notification_email" {
  description = "Email for alert notifications"
  type        = string
}

variable "notification_webhook_url" {
  description = "Webhook URL for Slack/Teams notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_cpu_threshold" {
  description = "CPU utilization threshold for alerts (%)"
  type        = number
  default     = 80
}

variable "alert_memory_threshold" {
  description = "Memory utilization threshold for alerts (%)"
  type        = number
  default     = 85
}

variable "alert_error_rate_threshold" {
  description = "Error rate threshold for alerts (%)"
  type        = number
  default     = 1
}

variable "alert_latency_p99_threshold" {
  description = "P99 latency threshold for alerts (seconds)"
  type        = number
  default     = 2
}

variable "enable_slack_notification" {
  description = "Enable Slack/Teams webhook notifications"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels for resources"
  type        = map(string)
  default     = {}
}
