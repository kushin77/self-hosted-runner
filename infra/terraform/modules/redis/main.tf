/**
 * Redis Memorystore Module - Main Configuration
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# REDIS INSTANCE
# ============================================================================

resource "google_redis_instance" "main" {
  project        = var.project_id
  name           = "${var.service_name}-redis-${var.environment}"
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  region         = var.region
  redis_version  = var.redis_version

  display_name = "Redis Cache - ${var.environment}"

  # Network configuration (private IP)
  authorized_network = var.network_id

  # Persistence
  persistence_config {
    persistence_mode    = var.enable_persistence ? "RDB" : "DISABLED"
    rdb_snapshot_period = "TWELVE_HOURS"
  }

  # Replication (only for standard tier)
  replica_count = var.tier == "standard" ? 1 : 0

  # Automation
  maintenance_policy {
    day            = "SUNDAY"
    hour           = 4
    update_channel = "STABLE"
  }

  # Auth
  auth_enabled = var.enable_auth
  auth_string  = var.enable_auth && var.auth_password != "" ? var.auth_password : null

  # Monitoring
  connect_mode = "PRIVATE_SERVICE_ACCESS"

  # Backup and recovery
  backup_configuration {
    # Standard tier supports RDB backup
  }

  labels = var.labels

  depends_on = [var.network_id]
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "google_project" "current" {
  project_id = var.project_id
}
