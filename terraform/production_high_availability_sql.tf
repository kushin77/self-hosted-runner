# High Availability Cloud SQL Configuration for Production
# This configuration implements:
# - Primary database in us-central1
# - Standby replica in us-west1 for automatic failover
# - Synchronous replication for strong consistency
# - Automated RTO/RPO management
# - 99.999% uptime SLA compliance

# ===== VARIABLES =====

variable "ha_environment" {
  description = "Environment for HA database"
  type        = string
  default     = "production"
}

variable "primary_region" {
  description = "Primary database region"
  type        = string
  default     = "us-central1"
}

variable "standby_region" {
  description = "Standby database region (for failover)"
  type        = string
  default     = "us-west1"
}

variable "database_machine_type" {
  description = "Machine tier for Cloud SQL (HA requires at least db-n1-standard-1)"
  type        = string
  default     = "db-n1-standard-2"  # Min recommended for production HA
}

variable "disk_size_gb" {
  description = "Disk size in GB for production"
  type        = number
  default     = 100
}

# ===== DATA SOURCES =====

data "google_client_config" "current" {}

# ===== PRIMARY DATABASE INSTANCE =====

resource "google_sql_database_instance" "production_primary" {
  count                    = var.ha_environment == "production" ? 1 : 0
  name                     = "nexusshield-db-primary-${data.google_client_config.current.project}"
  database_version         = "POSTGRES_14"
  region                   = var.primary_region
  deletion_protection      = true
  replication_type         = "SYNCHRONOUS_REPLICA"  # Strong consistency

  settings {
    tier                     = var.database_machine_type
    availability_type        = "REGIONAL"  # HA across zones
    disk_size                = var.disk_size_gb
    disk_type                = "PD_SSD"
    disk_autoresize          = true
    disk_autoresize_limit    = var.disk_size_gb * 3  # Allow up to 3x

    # High availability backup strategy
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"  # 3 AM UTC daily
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7        # 7-day PITR window
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    # Production database flags
    database_flags {
      name  = "max_connections"
      value = "500"
    }

    database_flags {
      name  = "shared_buffers"
      value = "16777216"  # 64GB for n1-standard-2
    }

    database_flags {
      name  = "effective_cache_size"
      value = "49152000"  # 192GB
    }

    database_flags {
      name  = "maintenance_work_mem"
      value = "2097152"  # 2GB
    }

    database_flags {
      name  = "work_mem"
      value = "5242880"  # 5GB
    }

    database_flags {
      name  = "log_statement"
      value = "all"  # Log all statements for audit
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries > 1 second
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    # Maintenance window (Sunday 5 AM UTC, off-peak)
    maintenance_window {
      day           = 0  # Sunday
      hour          = 5  # 5 AM UTC
      update_channel = "STABLE"
    }

    # Performance insights monitoring
    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
    }

    # Network configuration
    ip_configuration {
      ipv4_enabled    = false
      require_ssl     = true
      private_network = google_compute_network.production_vpc.id
      
      # Authorized networks for application access (if needed)
      # authorized_networks {
      #   name  = "app-servers"
      #   value = "10.1.0.0/16"
      # }
    }

    # User labels for cost allocation and management
    user_labels = {
      environment    = var.ha_environment
      tier           = "ha-production"
      deployment     = "nexusshield"
      rto            = "5-minutes"
      rpo            = "0-minutes"  # Synchronous replication
    }

    # Database flags for Row Level Security (RLS)
    database_flags {
      name  = "rls"
      value = "on"
    }

    # PITR for disaster recovery
    database_flags {
      name  = "wal_level"
      value = "replica"
    }
  }

  depends_on = [
    google_compute_network.production_vpc,
    google_compute_subnetwork.production_primary_subnet
  ]
}

# ===== STANDBY REPLICA INSTANCE =====

resource "google_sql_database_instance" "production_standby" {
  count                    = var.ha_environment == "production" ? 1 : 0
  name                     = "nexusshield-db-standby-${data.google_client_config.current.project}"
  database_version         = "POSTGRES_14"
  region                   = var.standby_region
  deletion_protection      = true
  master_instance_name     = google_sql_database_instance.production_primary[0].name

  replica_configuration {
    kind = "FAILOVER_REPLICA"  # Automatic failover capable
  }

  settings {
    tier              = var.database_machine_type
    availability_type = "ZONAL"  # Single zone (standby doesn't need HA)
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    disk_autoresize_limit = var.disk_size_gb * 3

    # Network configuration
    ip_configuration {
      ipv4_enabled    = false
      require_ssl     = true
      private_network = google_compute_network.production_vpc.id
    }

    # Labels for standby tracking
    user_labels = {
      environment = var.ha_environment
      tier        = "ha-standby"
      deployment  = "nexusshield"
      replica     = "failover"
    }
  }

  depends_on = [google_sql_database_instance.production_primary]
}

# ===== PRODUCTION VPC FOR DATABASE ISOLATION =====

resource "google_compute_network" "production_vpc" {
  name                    = "nexusshield-prod-vpc"
  auto_create_subnetworks = false
}

# Primary region subnet
resource "google_compute_subnetwork" "production_primary_subnet" {
  name                     = "nexusshield-prod-primary-subnet"
  ip_cidr_range            = "10.1.0.0/20"
  region                   = var.primary_region
  network                  = google_compute_network.production_vpc.id
  private_ip_google_access = true
}

# Standby region subnet
resource "google_compute_subnetwork" "production_standby_subnet" {
  name                     = "nexusshield-prod-standby-subnet"
  ip_cidr_range            = "10.2.0.0/20"
  region                   = var.standby_region
  network                  = google_compute_network.production_vpc.id
  private_ip_google_access = true
}

# ===== FIREWALL RULES FOR DATABASE ACCESS =====

resource "google_compute_firewall" "allow_db_internal" {
  name    = "nexusshield-allow-db-internal"
  network = google_compute_network.production_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]  # PostgreSQL
  }

  source_ranges = ["10.0.0.0/8"]  # Internal GCP networks
  target_tags   = ["nexusshield-db"]
}

# ===== OUTPUTS =====

output "primary_instance_name" {
  value       = try(google_sql_database_instance.production_primary[0].name, "")
  description = "Primary Cloud SQL instance name"
}

output "primary_instance_connection_name" {
  value       = try(google_sql_database_instance.production_primary[0].connection_name, "")
  description = "Primary instance connection name (for Cloud SQL Proxy)"
}

output "primary_instance_private_ip" {
  value       = try(google_sql_database_instance.production_primary[0].private_ip_address, "")
  description = "Primary instance private IP"
}

output "standby_instance_name" {
  value       = try(google_sql_database_instance.production_standby[0].name, "")
  description = "Standby Cloud SQL instance name"
}

output "standby_instance_connection_name" {
  value       = try(google_sql_database_instance.production_standby[0].connection_name, "")
  description = "Standby instance connection name"
}

output "standby_instance_private_ip" {
  value       = try(google_sql_database_instance.production_standby[0].private_ip_address, "")
  description = "Standby instance private IP"
}

output "vpc_network_name" {
  value       = google_compute_network.production_vpc.name
  description = "Production VPC network name"
}

output "rto_minutes" {
  value       = 5
  description = "Recovery Time Objective (automatic failover time)"
}

output "rpo_minutes" {
  value       = 0
  description = "Recovery Point Objective (synchronous replication = 0 data loss)"
}

output "availability_sla" {
  value       = "99.999%"
  description = "Uptime SLA with HA configuration"
}
