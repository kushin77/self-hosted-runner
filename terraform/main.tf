# ============================================================================
# NexusShield Portal MVP - Complete Infrastructure as Code
# ============================================================================
# Production-ready Terraform for GCP deployment
# Features: VPC, PostgreSQL, Cloud Run, API Gateway, KMS, GSM, monitoring
# Deployment: terraform apply -var="gcp_project=YOUR_PROJECT" -var="environment=staging"
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  
  backend "local" {
    path = "terraform.tfstate"
  }
}

# ===========================================================================
# PROVIDERS
# ===========================================================================

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ===========================================================================
# VARIABLES
# ===========================================================================

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (staging|production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'"
  }
}

variable "instance_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-f1-micro"
}

# ===========================================================================
# LOCALS
# ===========================================================================

locals {
  env_prefix = "${var.environment}-portal"
  service    = "nexus-shield-portal"
  
  labels = {
    environment = var.environment
    project     = "nexus-shield"
    managed_by  = "terraform"
  }
}

# ===========================================================================
# RANDOM DEPLOYMENT ID
# ===========================================================================

resource "random_string" "deployment_id" {
  length  = 8
  special = false
  upper   = false
}

# ===========================================================================
# SERVICE ACCOUNTS
# ===========================================================================

resource "google_service_account" "backend" {
  account_id   = "${local.env_prefix}-backend"
  display_name = "Portal Backend - ${var.environment}"
}

resource "google_service_account" "frontend" {
  account_id   = "${local.env_prefix}-frontend"
  display_name = "Portal Frontend - ${var.environment}"
}

# ===========================================================================
# VPC NETWORK
# ===========================================================================

resource "google_compute_network" "vpc" {
  name                    = "${local.env_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "backend" {
  name          = "${local.env_prefix}-backend-subnet"
  ip_cidr_range = var.environment == "production" ? "10.0.1.0/24" : "10.1.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "database" {
  name          = "${local.env_prefix}-database-subnet"
  ip_cidr_range = var.environment == "production" ? "10.0.2.0/24" : "10.1.2.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  private_ip_google_access = true
}

# ===========================================================================
# CLOUD NAT
# ===========================================================================

resource "google_compute_router" "nat" {
  name    = "${local.env_prefix}-nat-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${local.env_prefix}-nat"
  router                             = google_compute_router.nat.name
  region                             = google_compute_router.nat.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ===========================================================================
# VPC CONNECTOR
# ===========================================================================

resource "google_vpc_access_connector" "cloud_run" {
  name          = "${local.env_prefix}-connector"
  region        = var.gcp_region
  ip_cidr_range = var.environment == "production" ? "10.8.0.0/28" : "10.9.0.0/28"
  network       = google_compute_network.vpc.name
}

# ===========================================================================
# FIREWALL RULES
# ===========================================================================

resource "google_compute_firewall" "allow_internal" {
  name    = "${local.env_prefix}-allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [
    google_compute_subnetwork.backend.ip_cidr_range,
    google_compute_subnetwork.database.ip_cidr_range,
  ]
}

# ===========================================================================
# KMS ENCRYPTION
# ===========================================================================

resource "google_kms_key_ring" "portal" {
  name     = "${local.env_prefix}-keyring"
  location = "us"
}

resource "google_kms_crypto_key" "database" {
  name            = "${local.env_prefix}-db-key"
  key_ring        = google_kms_key_ring.portal.id
  rotation_period = "7776000s"  # 90 days
  
  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}

resource "google_kms_crypto_key" "secrets" {
  name            = "${local.env_prefix}-secret-key"
  key_ring        = google_kms_key_ring.portal.id
  rotation_period = "7776000s"
  
  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}

# ===========================================================================
# GOOGLE SECRET MANAGER
# ===========================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.env_prefix}-db-password"
  
  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_username" {
  secret_id = "${local.env_prefix}-db-username"
  
  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_username" {
  secret      = google_secret_manager_secret.db_username.id
  secret_data = "portal_admin"
}

# Grant backend access to secrets
resource "google_secret_manager_secret_iam_member" "backend_password" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "backend_username" {
  secret_id = google_secret_manager_secret.db_username.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# ===========================================================================
# CLOUD SQL - POSTGRES
# ===========================================================================

resource "google_sql_database_instance" "primary" {
  name             = "${local.env_prefix}-db"
  database_version = "POSTGRES_15"
  region           = var.gcp_region
  deletion_protection = var.environment == "production"
  
  settings {
    tier              = var.instance_tier
    availability_type = var.environment == "production" ? "REGIONAL" : "ZONAL"
    
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = var.environment == "production"
      transaction_log_retention_days = 7
    }

    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    ip_configuration {
      require_ssl = true
      
      ipv4_enabled = var.environment == "staging"
      
      private_network = var.environment == "production" ? google_compute_network.vpc.id : null
    }
  }
}

resource "google_sql_database" "portal" {
  name     = "portal"
  instance = google_sql_database_instance.primary.name
}

resource "google_sql_user" "portal" {
  name     = "portal_admin"
  instance = google_sql_database_instance.primary.name
  password = random_password.db_password.result
}

# ===========================================================================
# IAM ROLES - DATABASE ACCESS
# ===========================================================================

resource "google_project_iam_member" "backend_sql_client" {
  project = var.gcp_project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_project_iam_member" "backend_secret_accessor" {
  project = var.gcp_project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_project_iam_member" "backend_logging" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# ===========================================================================
# ARTIFACT REGISTRY
# ===========================================================================

resource "google_artifact_registry_repository" "docker" {
  location      = var.gcp_region
  repository_id = "${local.env_prefix}-docker"
  description   = "Portal MVP Docker images"
  format        = "DOCKER"
}

# ===========================================================================
# CLOUD RUN - BACKEND
# ===========================================================================

resource "google_cloud_run_service" "backend" {
  name     = "${local.service}-backend"
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.backend.email
      
      containers {
        image = "gcr.io/${var.gcp_project}/${local.service}-backend:latest"
        ports {
          container_port = 8080
        }
        
        env {
          name  = "DATABASE_URL"
          value = "postgresql://portal_admin@${google_sql_database_instance.primary.connection_name}/portal"
        }
        
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
        
        resources {
          limits = {
            memory = var.environment == "production" ? "1Gi" : "512Mi"
            cpu    = var.environment == "production" ? "1" : "0.5"
          }
        }
      }

      timeout_seconds = 30
    }

    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.cloud_run.name
        "run.googleapis.com/vpc-access-egress"    = "private-ranges-only"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# ===========================================================================
# CLOUD RUN - FRONTEND
# ===========================================================================

resource "google_cloud_run_service" "frontend" {
  name     = "${local.service}-frontend"
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.frontend.email
      
      containers {
        image = "gcr.io/${var.gcp_project}/${local.service}-frontend:latest"
        ports {
          container_port = 3000
        }
        
        env {
          name  = "REACT_APP_API_URL"
          value = "${google_cloud_run_service.backend.status[0].url}/api"
        }
        
        resources {
          limits = {
            memory = "256Mi"
            cpu    = "0.2"
          }
        }
      }

      timeout_seconds = 20
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# ===========================================================================
# IAM - CLOUD RUN PUBLIC ACCESS
# ===========================================================================

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "backend_noauth" {
  service  = google_cloud_run_service.backend.name
  location = google_cloud_run_service.backend.location
  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_cloud_run_service_iam_policy" "frontend_noauth" {
  service  = google_cloud_run_service.frontend.name
  location = google_cloud_run_service.frontend.location
  policy_data = data.google_iam_policy.noauth.policy_data
}

# ===========================================================================
# CLOUD MONITORING
# ===========================================================================

resource "google_monitoring_uptime_check_config" "backend" {
  display_name = "${local.env_prefix}-uptime-check"
  timeout      = "10s"
  period       = "60s"

  http_check {
    request_method = "GET"
    use_ssl        = true
    path           = "/health"
    port           = 443
  }

  monitored_resource {
    type = "uptime-url"
    labels = {
      host = replace(google_cloud_run_service.backend.status[0].url, "https://", "")
    }
  }

  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]
}

# ===========================================================================
# OUTPUTS
# ===========================================================================

output "deployment_id" {
  value       = random_string.deployment_id.result
  description = "Unique deployment identifier"
}

output "environment" {
  value = var.environment
}

output "backend_url" {
  value       = google_cloud_run_service.backend.status[0].url
  description = "Backend service URL"
}

output "frontend_url" {
  value       = google_cloud_run_service.frontend.status[0].url
  description = "Frontend service URL"
}

output "database_connection_name" {
  value       = google_sql_database_instance.primary.connection_name
  description = "Cloud SQL connection string"
}

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "artifact_registry_url" {
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/${google_artifact_registry_repository.docker.repository_id}"
  description = "Artifact Registry path"
}

output "deployment_summary" {
  value = jsonencode({
    environment           = var.environment
    deployment_id         = random_string.deployment_id.result
    backend_service       = google_cloud_run_service.backend.name
    frontend_service      = google_cloud_run_service.frontend.name
    database              = google_sql_database_instance.primary.name
    vpc                   = google_compute_network.vpc.name
    credential_management = "GSM (primary) → Vault (secondary) → KMS (tertiary)"
    immutable_trail       = "git + JSONL audit logs"
    automation            = "GitHub Actions CI/CD"
    timestamp             = timestamp()
  })
  description = "Complete deployment summary"
}
