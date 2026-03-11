/**
 * Terraform Variables
 * Configuration for NexusShield Portal infrastructure
 */

variable "gcp_project" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Deployment environment (development, staging, production)"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "app_name" {
  type        = string
  description = "Application name"
  default     = "nexusshield-portal"
}

variable "database_version" {
  type        = string
  description = "PostgreSQL version"
  default     = "15"
}

variable "database_tier" {
  type        = string
  description = "CloudSQL machine type"
  default     = "db-custom-4-16384"  # 4 vCPU, 16GB RAM
}

variable "redis_tier" {
  type        = string
  description = "Redis (Memorystore) tier size"
  default     = "basic"
}

variable "redis_memory_size_gb" {
  type        = number
  description = "Redis memory allocation in GB"
  default     = 5
}

variable "cloudrun_memory" {
  type        = string
  description = "Cloud Run memory allocation"
  default     = "1Gi"
}

variable "cloudrun_cpu" {
  type        = string
  description = "Cloud Run CPU allocation"
  default     = "2"
}

variable "cloudrun_max_instances" {
  type        = number
  description = "Cloud Run max instances for auto-scaling"
  default     = 10
}

variable "enable_monitoring" {
  type        = bool
  description = "Enable GCP Monitoring and alerting"
  default     = true
}

variable "enable_backup" {
  type        = bool
  description = "Enable automated database backups"
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Database backup retention in days"
  default     = 30
}
