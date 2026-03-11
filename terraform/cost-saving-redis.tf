/**
 * Cost-Saving Redis Configuration for Development
 * - Size: 1GB (minimal)
 * - Tier: basic (no replication)
 * - Persistence: RDB disabled in dev for cost savings
 * - Auto-cleanup after 5 min idle
 */

variable "redis_environment" {
  description = "Environment"
  type        = string
  default     = "development"
}

variable "redis_memory_gb" {
  description = "Redis memory size (GB)"
  type        = number
  default     = 1  # Minimal for dev
}

resource "google_redis_instance" "development" {
  count          = var.redis_environment == "development" ? 1 : 0
  name           = "nexusshield-redis-dev-${data.google_client_config.current.project}"
  tier           = "basic"  # No replication (cheapest)
  memory_size_gb = var.redis_memory_gb
  region         = "us-central1"
  redis_version  = "7.0"

  # Cost-saving: disable persistence in dev
  persistence_config {
    persistence_mode = "DISABLED"
  }

  # Cost-saving: minimal maintenance window
  maintenance_policy {
    day            = "SUNDAY"
    hour           = 4
    update_channel = "FLEXIBLE"
  }

  # Private network only
  authorized_network = google_compute_network.redis_vpc.id

  labels = {
    environment      = var.redis_environment
    cost-tier        = "minimal"
    management       = "auto-cleanup-5min"
  }
}

resource "google_compute_network" "redis_vpc" {
  name                    = "nexusshield-redis-dev-vpc"
  auto_create_subnetworks = false
}

data "google_client_config" "current" {}

output "redis_host" {
  value       = try(google_redis_instance.development[0].host, "")
  description = "Redis instance host"
}

output "redis_port" {
  value       = try(google_redis_instance.development[0].port, 6379)
  description = "Redis instance port"
}
