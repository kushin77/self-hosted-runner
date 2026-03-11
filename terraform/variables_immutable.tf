// ============================================================================
// TERRAFORM VARIABLES - IMMUTABLE & CREDENTIAL MANAGEMENT INFRASTRUCTURE
// ============================================================================

variable "gcp_project" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "Default GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment (staging|production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'"
  }
}

variable "organization_id" {
  description = "GCP Organization ID (for policies)"
  type        = string
  default     = ""
}

// Database configuration
variable "db_host" {
  description = "Database host"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "portal_db"
}

variable "db_instance_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-f1-micro"
}

// Credential Management
variable "vault_addr" {
  description = "HashiCorp Vault address"
  type        = string
  default     = "https://vault.example.com"
}

variable "vault_namespace" {
  description = "Vault namespace"
  type        = string
  default     = "admin"
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS verification for Vault (dev only!)"
  type        = bool
  default     = false
}

// Secret rotation settings
variable "secret_rotation_schedule" {
  description = "Cron schedule for secret rotation (UTC)"
  type        = string
  default     = "0 2 * * *" // 2 AM daily
}

variable "ephemeral_cleanup_schedule" {
  description = "Cron schedule for ephemeral resource cleanup"
  type        = string
  default     = "0 */6 * * *" // Every 6 hours
}

variable "ephemeral_resource_max_age_hours" {
  description = "Maximum age for ephemeral resources (hours)"
  type        = number
  default     = 24
}

// Cloud Run settings
variable "cloud_run_memory" {
  description = "Cloud Run memory allocation"
  type        = string
  default     = "512Mi"
}

variable "cloud_run_cpu" {
  description = "Cloud Run CPU allocation"
  type        = string
  default     = "1"
}

variable "cloud_run_timeout" {
  description = "Cloud Run timeout in seconds"
  type        = number
  default     = 300
}

variable "cloud_run_concurrency" {
  description = "Cloud Run max concurrent requests"
  type        = number
  default     = 100
}

// Deployment settings
variable "docker_registry_path" {
  description = "Artifact Registry path"
  type        = string
  default     = "us-central1-docker.pkg.dev"
}

variable "deployment_replicas" {
  description = "Number of Cloud Run replicas"
  type        = number
  default     = 3
}

// Audit settings
variable "audit_log_retention_days" {
  description = "Audit log retention period (days)"
  type        = number
  default     = 90
}

variable "immutable_audit_retention_days" {
  description = "Immutable audit trail retention (days)"
  type        = number
  default     = 365
}

// Monitoring and alerting
variable "enable_custom_metrics" {
  description = "Enable custom Cloud Monitoring metrics"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for critical alerts and operational notifications"
  type        = string
  default     = "ops@nexusshield.local"
}

// Tags and labels
variable "labels" {
  description = "Common labels for all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    team       = "platform"
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

// KMS encryption settings
variable "kms_rotation_period_days" {
  description = "KMS key rotation period (days)"
  type        = number
  default     = 90
}

variable "kms_protection_level" {
  description = "KMS key protection level (HSM|SOFTWARE)"
  type        = string
  default     = "HSM"
  validation {
    condition     = contains(["HSM", "SOFTWARE"], var.kms_protection_level)
    error_message = "Protection level must be HSM or SOFTWARE"
  }
}

// Feature flags
variable "enable_immutable_infrastructure" {
  description = "Enable immutable infrastructure patterns"
  type        = bool
  default     = true
}

variable "enable_automatic_cleanup" {
  description = "Enable automatic ephemeral resource cleanup"
  type        = bool
  default     = true
}

variable "enable_automatic_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = true
}

variable "enable_multi_cloud_vault" {
  description = "Enable Vault for multi-cloud credential management"
  type        = bool
  default     = true
}

variable "enable_zero_trust_security" {
  description = "Enable zero-trust security posture"
  type        = bool
  default     = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "uptime_check_period_seconds" {
  description = "Uptime check interval in seconds (60s default = 1 minute)"
  type        = number
  default     = 60
  validation {
    condition     = contains([60, 300, 900, 3600], var.uptime_check_period_seconds)
    error_message = "Period must be 60, 300, 900, or 3600 seconds"
  }
}

variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring uptime checks and alerts"
  type        = bool
  default     = true
}
