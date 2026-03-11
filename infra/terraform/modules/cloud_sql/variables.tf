/**
 * Cloud SQL Module - PostgreSQL Database
 * High-availability PostgreSQL with backups and SSL
 */

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for deployment"
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

variable "database_version" {
  description = "PostgreSQL version (e.g., POSTGRES_15)"
  type        = string
  default     = "POSTGRES_15"
}

variable "database_size" {
  description = "Machine type for Cloud SQL instance"
  type        = string
  default     = "db-custom-1-4096"  # 1 CPU, 4GB RAM
}

variable "database_storage_gb" {
  description = "Storage size in GB"
  type        = number
  default     = 100
}

variable "enable_high_availability" {
  description = "Enable HA with regional replica"
  type        = bool
  default     = true
}

variable "backup_location" {
  description = "Backup location (multi-region recommended)"
  type        = string
  default     = "us"
}

variable "database_password" {
  description = "Database root password (from Secret Manager in production)"
  type        = string
  sensitive   = true
}

variable "network_id" {
  description = "VPC network ID for private service connection"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    module = "cloud_sql"
  }
}
