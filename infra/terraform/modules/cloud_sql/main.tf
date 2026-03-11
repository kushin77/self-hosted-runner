/**
 * Cloud SQL Module - Main Configuration
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
# CLOUD SQL INSTANCE
# ============================================================================

resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = "${var.service_name}-db-${var.environment}"
  database_version    = var.database_version
  region              = var.region
  deletion_protection = var.environment == "prod" ? true : false

  settings {
    tier                  = var.database_size
    availability_type     = var.enable_high_availability ? "REGIONAL" : "ZONAL"
    disk_size             = var.database_storage_gb
    disk_type             = "PD_SSD"
    disk_autoresize       = true
    disk_autoresize_limit = 500
    user_labels           = var.labels
    password_validation_policy {
      require_uppercase = true
      require_lowercase = true
      require_numbers   = true
      require_symbols   = true
      min_length        = 12
    }

    # Backups
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00" # 2 AM UTC
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
      location = var.backup_location
    }

    # IP configuration (private IP only)
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true

      authorized_networks {
        name  = "Cloud Run"
        value = "0.0.0.0/0" # Restricted by VPC connector in production
      }
    }

    # Database flags
    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    database_flags {
      name  = "log_statement"
      value = "all" # Log all statements for audit (disable in prod for performance)
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000" # Log queries longer than 1 second
    }

    # Insights
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }


}

# ============================================================================
# HIGH AVAILABILITY REPLICA (if enabled)
# ============================================================================

resource "google_sql_database_instance" "replica" {
  count                = var.enable_high_availability ? 1 : 0
  project              = var.project_id
  name                 = "${var.service_name}-db-replica-${var.environment}"
  database_version     = var.database_version
  region               = var.region
  master_instance_name = google_sql_database_instance.main.name

  replica_configuration {
    ca_certificate     = ""
    client_certificate = ""
    client_key         = ""
    kind               = "sql#replicaConfiguration"
    mysql_replica_configuration {
      ca_certificate          = ""
      client_certificate      = ""
      client_key              = ""
      master_heartbeat_period = ""
      password                = ""
      ssl_cipher              = ""
      username                = ""
    }
    postgresql_replica_configuration {
    }
    server_ca_cert = ""
  }

  deletion_protection = false

  depends_on = [google_sql_database_instance.main]
}

# ============================================================================
# DATABASE
# ============================================================================

resource "google_sql_database" "main" {
  name      = "nexus_shield"
  instance  = google_sql_database_instance.main.name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# ============================================================================
# ROOT USER PASSWORD
# ============================================================================

resource "google_sql_user" "root" {
  name     = "root"
  instance = google_sql_database_instance.main.name
  password = var.database_password
  type     = "PASSWORD_TYPE_POSTGRES"
}

# ============================================================================
# APPLICATION USER
# ============================================================================

resource "random_password" "app_user_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "app_user" {
  name     = "app_user"
  instance = google_sql_database_instance.main.name
  password = random_password.app_user_password.result
  type     = "PASSWORD_TYPE_POSTGRES"

  depends_on = [google_sql_user.root]
}

/* Database initialization helper removed (provider compatibility). */

# ============================================================================
# BACKUP
# ============================================================================

resource "google_sql_backup_run" "manual_backup" {
  count       = var.environment == "prod" ? 1 : 0
  instance    = google_sql_database_instance.main.name
  description = "Manual backup created by Terraform"
  depends_on  = [google_sql_user.app_user]
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "google_project" "current" {
  project_id = var.project_id
}
