/**
 * Cost-Saving Cloud SQL Configuration for Development
 * - Tier: db-f1-micro for development (most economical)
 * - Automatic backup: disabled in dev
 * - Maintenance: Sunday 4 AM UTC
 * - Connector for VPC access
 */

variable "cloudsql_environment" {
  description = "Environment"
  type        = string
  default     = "development"
}

variable "database_machine_type" {
  description = "Machine tier for Cloud SQL"
  type        = string
  default     = "db-f1-micro"  # ~$10/month in dev
}

resource "google_sql_database_instance" "development" {
  count             = var.cloudsql_environment == "development" ? 1 : 0
  name              = "nexusshield-db-dev-${data.google_client_config.current.project}"
  database_version  = "POSTGRES_14"
  region            = "us-central1"
  deletion_protection = false

  settings {
    tier              = var.database_machine_type
    availability_type = "ZONAL"  # Single zone for cost savings
    disk_size         = 10
    disk_type         = "PD_SSD"
    disk_autoresize   = false

    # Disable expensive features in dev
    backup_configuration {
      enabled = false  # No backups in dev
    }

    # Cost optimization flags
    database_flags {
      name  = "log_statement"
      value = "none"  # Disable logging for performance
    }

    database_flags {
      name  = "shared_buffers"
      value = "262144"  # Minimal for micro instance
    }

    maintenance_window {
      day           = 0  # Sunday
      hour          = 4  # 4 AM UTC
      update_channel = "STABLE"
    }

    ip_configuration {
      ipv4_enabled    = false
      require_ssl     = true
      private_network = google_compute_network.dev_vpc.id
    }

    # User labels for cost tracking
    user_labels = {
      environment = var.cloudsql_environment
      cost-tier   = "minimal"
    }
  }
}

# Scheduled shutdown for dev databases (if using scheduling)
resource "google_sql_database_instance" "scheduled_shutdown_metadata" {
  count = var.cloudsql_environment == "development" ? 1 : 0
  
  depends_on = [google_sql_database_instance.development]
  
  # Metadata for external cleanup scripts
  # Note: Cloud SQL doesn't support native scheduling; use external cleanup service
}

# Note: data "google_client_config" "current" defined in cost-saving-cloudrun.tf (avoid duplicates)

resource "google_compute_network" "dev_vpc" {
  name                    = "nexusshield-dev-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "dev_subnet" {
  name            = "nexusshield-dev-subnet"
  ip_cidr_range   = "10.40.0.0/20"
  region          = "us-central1"
  network         = google_compute_network.dev_vpc.id
  private_ip_google_access = true
}

output "database_instance_name" {
  value       = try(google_sql_database_instance.development[0].name, "")
  description = "Cloud SQL instance name"
}

output "database_private_ip" {
  value       = try(google_sql_database_instance.development[0].private_ip_address, "")
  description = "Database private IP address"
}
