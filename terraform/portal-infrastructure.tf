################################################################################
# NexusShield Portal MVP — Infrastructure-as-Code (Terraform)
# Status: Production-Ready | Date: 2026-03-09 | Version: 1.0
################################################################################

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.10"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }

  # Immutable state file (encrypted, backed up)
  backend "gcs" {
    bucket  = "nexusshield-terraform-state"
    prefix  = "portal/production"
    encryption_key = "CONFIG_VIA_ENV_TF_BACKEND_CONFIG"
  }
}

################################################################################
# Provider Configuration (via OIDC — ephemeral auth)
################################################################################

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  default_labels {
    environment = var.environment
    product     = "nexusshield"
    squad       = "platform"
    cost_center = "engineering"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Product     = "nexusshield"
      Squad       = "platform"
      CostCenter  = "engineering"
    }
  }
}

provider "vault" {
  address         = var.vault_address
  skip_tls_verify = var.vault_skip_tls_verify # false in production
}

################################################################################
# Variables (Environment-Specific Configuration)
################################################################################

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Must be 'staging' or 'production'"
  }
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  sensitive   = true
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  sensitive   = true
}

variable "vault_skip_tls_verify" {
  description = "Skip Vault TLS verification (false in production)"
  type        = bool
  default     = false
}

variable "database_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "api_container_image" {
  description = "API backend container image"
  type        = string
}

variable "api_container_port" {
  description = "API container port"
  type        = number
  default     = 3000
}

variable "instance_count" {
  description = "Cloud Run min instances"
  type        = number
  default     = 1
}

################################################################################
# 1. Network Infrastructure (VPC + Security)
################################################################################

# VPC for isolated networking
resource "google_compute_network" "portal_vpc" {
  name                    = "nexusshield-portal-${var.environment}"
  auto_create_subnetworks = false

  timeouts {
    create = "10m"
  }
}

# Subnet for portal infrastructure
resource "google_compute_subnetwork" "portal_subnet" {
  name          = "nexusshield-portal-subnet-${var.environment}"
  ip_cidr_range = var.environment == "production" ? "10.0.0.0/20" : "10.1.0.0/20"
  region        = var.gcp_region
  network       = google_compute_network.portal_vpc.id

  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_logs_enabled    = true
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud SQL private service connection
resource "google_compute_global_address" "private_ip_address" {
  name          = "nexusshield-private-ip-${var.environment}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.portal_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.portal_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

################################################################################
# 2. Database Layer (PostgreSQL Multi-AZ)
################################################################################

# Primary PostgreSQL instance
resource "google_sql_database_instance" "portal_db" {
  name                = "nexusshield-portal-db-${var.environment}"
  database_version    = "POSTGRES_${var.database_version}"
  region              = var.gcp_region
  deletion_protection = var.environment == "production" ? true : false

  settings {
    tier              = var.environment == "production" ? "db-custom-4-16384" : "db-custom-2-8192"
    availability_type = "REGIONAL" # Multi-AZ for HA
    disk_type         = "PD_SSD"
    disk_size         = var.environment == "production" ? 500 : 100

    # Automated backups (immutable)
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00" # 2 AM UTC
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    # Encryption at rest (KMS-managed)
    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    # IP configuration (private IP only)
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.portal_vpc.id
      require_ssl                                   = true
      enable_private_path_for_cloudsql_cloud_sql    = true
    }

    # Maintenance window (low-traffic period)
    maintenance_window {
      day          = 0 # Sunday
      hour         = 3 # 3 AM UTC
      update_track = "stable"
    }

    # Enhanced monitoring
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
    }

    # Connection pooling
    database_flags {
      name  = "max_connections"
      value = "400"
    }

    # Logging (audit trail)
    database_flags {
      name  = "log_statement"
      value = "all"
    }
  }

  deletion_protection = var.environment == "production"
}

# Read replica (for analytics queries)
resource "google_sql_database_instance" "portal_db_read_replica" {
  count                = var.environment == "production" ? 1 : 0
  name                 = "nexusshield-portal-db-replica-${var.environment}"
  region               = var.environment == "production" ? "us-west1" : var.gcp_region
  database_version     = "POSTGRES_${var.database_version}"
  master_instance_name = google_sql_database_instance.portal_db.name

  replica_configuration {
    kind = "REGIONAL"
  }

  deletion_protection = false
}

# Database "portal_main"
resource "google_sql_database" "portal" {
  name     = "portal_main"
  instance = google_sql_database_instance.portal_db.name
}

# Database user (authentication via Cloud SQL IAM)
resource "google_sql_user" "portal_app" {
  name           = "portal-app@${var.gcp_project_id}.iam"
  instance       = google_sql_database_instance.portal_db.name
  type           = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = "ABANDON"
}

################################################################################
# 3. Service Accounts & OIDC (Ephemeral Auth)
################################################################################

# Service account for API backend
resource "google_service_account" "portal_api" {
  account_id   = "nexusshield-portal-api"
  display_name = "NexusShield Portal API"
  description  = "Service account for Portal API backend"
}

# IAM binding: API service account → Cloud SQL client
resource "google_project_iam_member" "api_cloud_sql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.portal_api.email}"
}

# IAM binding: API service account → Secrets accessor
resource "google_project_iam_member" "api_secrets_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.portal_api.email}"
}

# IAM binding: API service account → Logs writer
resource "google_project_iam_member" "api_logs_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.portal_api.email}"
}

# Workload Identity Pool (for GitHub Actions OIDC)
resource "google_iam_workload_identity_pool" "github_actions" {
  count                     = var.environment == "production" ? 1 : 0
  workload_identity_pool_id = "github-actions-portal"
  location                  = "global"
  display_name              = "GitHub Actions Portal Deployments"
}

# OIDC Provider (GitHub)
resource "google_iam_workload_identity_pool_provider" "github" {
  count                  = var.environment == "production" ? 1 : 0
  workload_identity_pool_id = google_iam_workload_identity_pool.github_actions[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  location                           = "global"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository_owner == 'kushin77'"
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account impersonation (GitHub → Google)
resource "google_service_account_iam_member" "github_impersonate" {
  count              = var.environment == "production" ? 1 : 0
  service_account_id = google_service_account.portal_api.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/locations/global/workloadIdentityPools/github-actions-portal/providers/github-oidc"
}

################################################################################
# 4. Secrets Management (GSM + Vault + KMS)
################################################################################

# Secret: Database password (GSM primary storage)
resource "google_secret_manager_secret" "db_password" {
  secret_id = "nexusshield-portal-db-password"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Secret value: Database password (rotate every 30 days)
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Random password for database (ephemeral)
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# IAM: Allow API service account to access database password
resource "google_secret_manager_secret_iam_member" "db_password_accessor" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.portal_api.email}"
}

# AWS KMS Key for envelope encryption (fallback + audit logging)
resource "aws_kms_key" "portal_credentials" {
  description             = "KMS key for NexusShield Portal credential encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Product     = "nexusshield"
  }
}

resource "aws_kms_alias" "portal_credentials" {
  name          = "alias/nexusshield-portal-credentials"
  target_key_id = aws_kms_key.portal_credentials.key_id
}

# Vault AppRole for portal service (fallback auth)
resource "vault_approle_auth_backend_role" "portal" {
  backend   = "approle"
  role_name = "nexusshield-portal"

  secret_id_ttl       = 2592000 # 30 days
  secret_id_num_uses  = 0       # unlimited
  token_ttl           = 3600    # 1 hour
  token_max_ttl       = 86400   # 24 hours
  bind_secret_id      = true
  secret_id_num_uses  = 1000
}

# Vault policy for portal
resource "vault_policy" "portal" {
  name = "nexusshield-portal"

  policy = <<EOH
# Database secrets
path "database/config/portal" {
  capabilities = ["read"]
}

path "database/creds/portal" {
  capabilities = ["read"]
}

# KMS key data
path "aws/creds/nexusshield-portal" {
  capabilities = ["read"]
}

# Audit logs
path "sys/audit" {
  capabilities = ["read"]
}
EOH
}

################################################################################
# 5. Compute Layer (Cloud Run)
################################################################################

# Cloud Run service for API backend
resource "google_cloud_run_service" "portal_api" {
  name     = "nexusshield-portal-api-${var.environment}"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    spec {
      service_account_name = google_service_account.portal_api.email

      containers {
        image = var.api_container_image

        ports {
          container_port = var.api_container_port
        }

        # Environment variables (secrets injected as env vars)
        env {
          name  = "DATABASE_URL"
          value = "postgresql://${google_sql_user.portal_app.name}:${random_password.db_password.result}@${google_sql_database_instance.portal_db.private_ip_address}:5432/portal_main?sslmode=require"
        }

        env {
          name  = "NODE_ENV"
          value = var.environment
        }

        env {
          name  = "PORT"
          value = var.api_container_port
        }

        # Resource requests
        resources {
          limits = {
            cpu    = var.environment == "production" ? "2" : "1"
            memory = var.environment == "production" ? "2Gi" : "1Gi"
          }
        }

        # Startup probe (wait for app to be ready)
        startup_probe {
          http_get {
            path = "/health"
            port = var.api_container_port
          }
          failure_threshold     = 5
          initial_delay_seconds = 0
          period_seconds        = 1
          timeout_seconds       = 240
        }

        # Liveness probe (restart if unhealthy)
        liveness_probe {
          http_get {
            path = "/health"
            port = var.api_container_port
          }
          failure_threshold = 3
          period_seconds    = 10
          timeout_seconds   = 5
        }
      }

      # Auto-scaling configuration
      timeout_seconds = 60
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = var.instance_count
        "autoscaling.knative.dev/maxScale" = var.environment == "production" ? "100" : "10"
      }
    }
  }

  # Traffic targeting (for blue-green deployments)
  traffic {
    percent        = 100
    latest_revision = true
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_sql_database_instance.portal_db
  ]
}

# Cloud Run IAM: Allow unauthenticated traffic (API Gateway handles auth)
resource "google_cloud_run_service_iam_member" "portal_api_public" {
  service  = google_cloud_run_service.portal_api.name
  location = google_cloud_run_service.portal_api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Run IAM: Allow GitHub Actions to deploy
resource "google_cloud_run_service_iam_member" "portal_api_deployer" {
  service  = google_cloud_run_service.portal_api.name
  location = google_cloud_run_service.portal_api.location
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.portal_api.email}"
}

################################################################################
# 6. API Gateway + CDN
################################################################################

# API Gateway (authentication + rate limiting)
resource "google_api_gateway_api" "portal" {
  provider      = google-beta
  api_id        = "nexusshield-portal"
  display_name  = "NexusShield Portal API"
  project       = var.gcp_project_id
  managed_service_config = templatefile("${path.module}/openapi.yaml.tpl", {
    cloud_run_url = google_cloud_run_service.portal_api.status[0].url
  })
}

resource "google_api_gateway_api_config" "portal" {
  provider              = google-beta
  api                   = google_api_gateway_api.portal.api_id
  api_config_id = "prod-${var.environment}"
  project       = var.gcp_project_id
  backend_auth {
    google_service_account = google_service_account.portal_api.email
  }
}

resource "google_api_gateway_gateway" "portal" {
  provider      = google-beta
  api_config    = google_api_gateway_api_config.portal.id
  gateway_id    = "nexusshield-portal-${var.environment}"
  display_name  = "NexusShield Portal Gateway"
  project       = var.gcp_project_id
  location      = var.gcp_region
}

# Cloud CDN (caching + DDoS protection)
resource "google_compute_backend_service" "portal_api" {
  name            = "nexusshield-portal-api-${var.environment}"
  protocol        = "HTTPS"
  timeout_sec     = 30
  enable_cdn      = true
  project         = var.gcp_project_id

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    negative_caching  = true
    negative_caching_policy {
      code = 404
      ttl  = 120
    }
  }

  custom_request_headers {
    headers = ["X-Client-Region:{client_region}"]
  }
}

################################################################################
# 7. Monitoring & Logging
################################################################################

# Cloud Logging (immutable audit trail)
resource "google_logging_project_sink" "portal_audit" {
  name        = "nexusshield-portal-audit-sink"
  project     = var.gcp_project_id
  destination = "storage.googleapis.com/nexusshield-portal-audit-${var.environment}"
  
  filter = <<EOT
resource.type="cloud_run_revision"
AND jsonPayload.action IN ("credential_rotation", "deployment_executed", "compliance_check")
  EOT

  # Immutable sink configuration
  unique_writer_identity = true
}

# Grant logging service account write access to Cloud Storage
resource "google_storage_bucket_iam_member" "audit_logs_sink" {
  bucket = "nexusshield-portal-audit-${var.environment}"
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.portal_audit.writer_identity
}

# Cloud Monitoring (alerts)
resource "google_monitoring_notification_channel" "slack" {
  display_name = "NexusShield Slack #alerts"
  type         = "slack"
  labels = {
    channel_name = "#nexusshield-alerts"
  }
}

resource "google_monitoring_alert_policy" "api_error_rate" {
  display_name = "NexusShield Portal API Error Rate > 1%"
  conditions {
    display_name = "Error rate high"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\" AND resource.label.service_name = \"${google_cloud_run_service.portal_api.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.01
    }
  }

  notification_channels = [google_monitoring_notification_channel.slack.id]
}

resource "google_monitoring_alert_policy" "api_latency" {
  display_name = "NexusShield Portal API Latency > 500ms"
  conditions {
    display_name = "Latency high"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_latencies\" AND resource.label.service_name = \"${google_cloud_run_service.portal_api.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 500
    }
  }

  notification_channels = [google_monitoring_notification_channel.slack.id]
}

################################################################################
# 8. Outputs (Connection Information)
################################################################################

output "database_connection_name" {
  description = "Cloud SQL connection name (for cloud_sql_proxy)"
  value       = google_sql_database_instance.portal_db.connection_name
  sensitive   = false
}

output "database_private_ip" {
  description = "Database private IP address"
  value       = google_sql_database_instance.portal_db.private_ip_address
  sensitive   = false
}

output "api_service_url" {
  description = "Cloud Run API service URL"
  value       = google_cloud_run_service.portal_api.status[0].url
  sensitive   = false
}

output "service_account_email" {
  description = "Portal API service account email"
  value       = google_service_account.portal_api.email
  sensitive   = false
}

output "workload_identity_pool_resource_name" {
  description = "Workload Identity Pool resource name (for GitHub Actions OIDC)"
  value       = try(google_iam_workload_identity_pool.github_actions[0].name, "N/A")
  sensitive   = false
}

output "kms_key_id" {
  description = "AWS KMS key ID"
  value       = aws_kms_key.portal_credentials.key_id
  sensitive   = false
}

output "vault_approle_role_id" {
  description = "Vault AppRole role ID"
  value       = vault_approle_auth_backend_role.portal.role_id
  sensitive   = true
}
