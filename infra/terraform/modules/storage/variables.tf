/**
 * Storage/GCS Module - Artifact and State Storage
 * Manages cloud storage for Terraform state, backups, and container artifacts
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Primary region for storage buckets"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "service_name" {
  description = "Service name prefix for resource naming"
  type        = string
  default     = "nexus-shield"
}

variable "enable_versioning" {
  description = "Enable bucket versioning"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Object retention days for audit logs"
  type        = number
  default     = 90
}

variable "enable_encryption" {
  description = "Enable bucket encryption"
  type        = bool
  default     = true
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access control"
  type        = bool
  default     = true
}

variable "public_access_prevention" {
  description = "Prevent public access to buckets"
  type        = string
  default     = "enforced"
}

variable "audit_logs_retention_days" {
  description = "Retention period for audit logs in days"
  type        = number
  default     = 365
}

variable "backup_retention_days" {
  description = "Retention period for database backups in days"
  type        = number
  default     = 30
}

variable "service_account_email" {
  description = "Service account email for read/write access"
  type        = string
}

variable "terraform_service_account_email" {
  description = "Service account email for Terraform state backend"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    module = "storage"
  }
}
