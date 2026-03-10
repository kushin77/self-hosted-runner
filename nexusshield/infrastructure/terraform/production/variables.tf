###############################################################################
# NexusShield Portal Infrastructure - Terraform Variables
#
# Purpose: Define all input variables for production infrastructure deployment
# Format: Organized by functional area (GCP settings, Database, Network, etc)
###############################################################################

###############################################################################
# GCP Project Configuration
###############################################################################

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "nexusshield-prod"
}

variable "gcp_region" {
  description = "GCP Region for resources (e.g., us-central1, us-east1)"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}

###############################################################################
# Database Selection & Configuration
###############################################################################

variable "use_firestore" {
  description = "Use Cloud Firestore instead of Cloud SQL (bypasses org policy constraints)"
  type        = bool
  default     = true

  validation {
    condition     = can(var.use_firestore)
    error_message = "use_firestore must be a boolean (true or false)."
  }
}

variable "db_version" {
  description = "PostgreSQL version for Cloud SQL (ignored if use_firestore=true)"
  type        = string
  default     = "15"
}

variable "db_instance_class" {
  description = "Cloud SQL instance machine type (ignored if use_firestore=true)"
  type        = string
  default     = "db-f1-micro"
}

###############################################################################
# Cloud Run Configuration
###############################################################################

variable "portal_image" {
  description = "Portal backend Docker image URL (from Artifact Registry or GCR)"
  type        = string
  default     = "gcr.io/nexusshield-prod/portal-backend:latest"
}

variable "portal_memory" {
  description = "Cloud Run service memory allocation (e.g., 512Mi, 1Gi, 2Gi)"
  type        = string
  default     = "512Mi"
}

variable "portal_timeout" {
  description = "Cloud Run service timeout in seconds"
  type        = number
  default     = 300
}

variable "portal_max_instances" {
  description = "Cloud Run maximum concurrent instances"
  type        = number
  default     = 100
}

variable "portal_backend_sa_email" {
  description = "Service account email for Portal backend (use pre-created or auto-generated)"
  type        = string
  default     = "" # If empty, service account will be created from scratch
}

###############################################################################
# Network & Security
###############################################################################

variable "allow_public" {
  description = "Allow public (allUsers) access to Cloud Run service"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for VPC network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.40.0.0/20"
}

###############################################################################
# Secret Management
###############################################################################

variable "secret_rotation_days" {
  description = "Rotate database password every N days"
  type        = number
  default     = 30
}

###############################################################################
# Tagging & Labels
###############################################################################

variable "labels" {
  description = "Common labels applied to all resources"
  type        = map(string)
  default = {
    managed_by  = "terraform"
    application = "nexusshield-portal"
    environment = "production"
  }
}

###############################################################################
# Feature Flags
###############################################################################

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and Cloud Logging"
  type        = bool
  default     = true
}

variable "enable_tracing" {
  description = "Enable Cloud Trace for distributed tracing"
  type        = bool
  default     = true
}

variable "enable_profiling" {
  description = "Enable Cloud Profiler for production profiling"
  type        = bool
  default     = false
}
