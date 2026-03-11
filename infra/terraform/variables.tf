/**
 * Root Configuration Variables
 * Passes through to all modules with environment-specific customization
 */

# ============================================================================
# PROJECT & REGION
# ============================================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "us-central1"
}

variable "secondary_region" {
  description = "Secondary region for multi-region resources"
  type        = string
  default     = "us-east1"
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# ============================================================================
# PRODUCT & SERVICE
# ============================================================================

variable "service_name" {
  description = "Service name"
  type        = string
  default     = "nexus-shield"
}

variable "product_name" {
  description = "Product name"
  type        = string
  default     = "NexusShield"
}

# ============================================================================
# CONTAINER IMAGES
# ============================================================================

variable "backend_image" {
  description = "Backend container image URL"
  type        = string
}

variable "frontend_image" {
  description = "Frontend container image URL"
  type        = string
}

# ============================================================================
# COMPUTE RESOURCES
# ============================================================================

variable "backend_memory" {
  description = "Backend container memory (e.g., '1Gi')"
  type        = string
  default     = "1Gi"
}

variable "backend_cpu" {
  description = "Backend CPU cores"
  type        = string
  default     = "1"
}

variable "frontend_memory" {
  description = "Frontend container memory (e.g., '512Mi')"
  type        = string
  default     = "512Mi"
}

variable "frontend_cpu" {
  description = "Frontend CPU cores"
  type        = string
  default     = "1"
}

variable "cloud_run_min_instances" {
  description = "Minimum Cloud Run instances"
  type        = number
  default     = 1
}

variable "cloud_run_max_instances" {
  description = "Maximum Cloud Run instances"
  type        = number
  default     = 10
}

# ============================================================================
# DATABASE
# ============================================================================

variable "database_machine_type" {
  description = "Cloud SQL machine type"
  type        = string
  default     = "db-custom-1-4096"
}

variable "database_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "enable_database_ha" {
  description = "Enable Cloud SQL High Availability"
  type        = bool
  default     = true
}

variable "backup_location" {
  description = "Backup location for Cloud SQL"
  type        = string
  default     = "us"
}

# ============================================================================
# CACHE
# ============================================================================

variable "redis_tier" {
  description = "Redis tier (basic/standard)"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["basic", "standard"], var.redis_tier)
    error_message = "Redis tier must be basic or standard."
  }
}

variable "redis_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 4
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "7.x"
}

# ============================================================================
# SECURITY
# ============================================================================

variable "enable_encryption" {
  description = "Enable KMS encryption for storage"
  type        = bool
  default     = true
}

variable "enable_wif" {
  description = "Enable Workload Identity Federation"
  type        = bool
  default     = true
}

# ============================================================================
# NETWORKING
# ============================================================================

variable "enable_nat_gateway" {
  description = "Enable Cloud NAT for outbound traffic"
  type        = bool
  default     = true
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for frontend"
  type        = bool
  default     = true
}

# ============================================================================
# LABELS
# ============================================================================

variable "labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "nexus-shield"
  }
}

# ============================================================================
# SECRETS
# ============================================================================

variable "redis_auth_password" {
  description = "Redis AUTH password"
  type        = string
  sensitive   = true
}

variable "database_root_password" {
  description = "Database root password"
  type        = string
  sensitive   = true
}

variable "backend_env_vars" {
  description = "Backend environment variables"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "uptime_token_secret_name" {
  description = "Secret Manager secret name for uptime check token (optional)"
  type        = string
  default     = ""
}
