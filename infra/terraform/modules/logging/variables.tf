/**
 * Cloud Logging Module - Log Sinks, Aggregation, Audit Trail
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_name" {
  description = "Service name"
  type        = string
  default     = "nexus-shield"
}

variable "logs_bucket_location" {
  description = "Cloud Logging bucket location"
  type        = string
  default     = "us-central1"
}

variable "audit_logs_retention_days" {
  description = "Audit logs retention in days"
  type        = number
  default     = 365
}

variable "application_logs_retention_days" {
  description = "Application logs retention in days"
  type        = number
  default     = 90
}

variable "labels" {
  description = "Labels for resources"
  type        = map(string)
  default     = {}
}
