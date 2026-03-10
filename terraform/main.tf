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

# ==========================================================================
# PROVIDERS
# ===========================================================================

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ==========================================================================
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

# ==========================================================================
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

# ==========================================================================
# RANDOM DEPLOYMENT ID
# ===========================================================================

resource "random_string" "deployment_id" {
  length  = 8
  special = false
  upper   = false
}

# ==========================================================================
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

# ==========================================================================
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

# ==========================================================================
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

# ==========================================================================
# VPC CONNECTOR
# ===========================================================================

resource "google_vpc_access_connector" "cloud_run" {
  # Use an explicit, RFC-compliant name for production to satisfy GCP's
  # connector ID pattern. For non-production environments, keep the
  # generated prefix-based name.
  name = var.environment == "production" ? "production-portal-connector" : "${local.env_prefix}-connector"
  region        = var.gcp_region
  ip_cidr_range = var.environment == "production" ? "10.8.0.0/28" : "10.9.0.0/28"
  network       = google_compute_network.vpc.self_link
}

# ==========================================================================
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

# ==========================================================================
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

# ==========================================================================
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
