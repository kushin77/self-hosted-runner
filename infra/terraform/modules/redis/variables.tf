/**
 * Redis Memorystore Module - In-Memory Cache Layer
 * High-availability Redis with replication and persistence
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

variable "tier" {
  description = "Tier of the Redis instance (basic or standard)"
  type        = string
  default     = "standard"  # HA with replication

  validation {
    condition     = contains(["basic", "standard"], var.tier)
    error_message = "Tier must be either 'basic' or 'standard'."
  }
}

variable "memory_size_gb" {
  description = "Memory size in GB"
  type        = number
  default     = 4

  validation {
    condition     = var.memory_size_gb >= 1 && var.memory_size_gb <= 300
    error_message = "Memory size must be between 1 and 300 GB."
  }
}

variable "redis_version" {
  description = "Redis version (e.g., redis_7_x)"
  type        = string
  default     = "redis_7_x"
}

variable "enable_persistence" {
  description = "Enable RDB persistence"
  type        = bool
  default     = true
}

variable "enable_auth" {
  description = "Enable AUTH password"
  type        = bool
  default     = true
}

variable "auth_password" {
  description = "Redis AUTH password (from Secret Manager in production)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "network_id" {
  description = "VPC network ID for private access"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    module = "redis"
  }
}
