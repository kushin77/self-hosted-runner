terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "environment" {
  type = string
}

variable "service_name" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "notification_channels" {
  description = "Optional list of notification channel resource IDs for alerting"
  type        = list(string)
  default     = []
}

module "monitoring" {
  source = "../modules/monitoring"

  project_id                = var.project_id
  environment               = var.environment
  service_name              = var.service_name
  notification_email        = "ops@example.com"
  enable_slack_notification = false
  labels                    = var.labels
  # Optional: pass notification channels (list of notification channel resource IDs)
  notification_channels    = var.notification_channels
}

module "logging" {
  source = "../modules/logging"

  project_id   = var.project_id
  environment  = var.environment
  service_name = var.service_name
  labels       = var.labels
}

# Generate a long-lived random token to use for uptime check auth header.
resource "random_password" "uptime_token" {
  length           = 48
  special          = false
}

# Store the token in Secret Manager (replication = automatic)
resource "google_secret_manager_secret" "uptime_token" {
  secret_id = "uptime-check-token"
  project   = var.project_id

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "uptime_token" {
  secret      = google_secret_manager_secret.uptime_token.id
  secret_data = random_password.uptime_token.result
}

# Enable health checks with auth header using the stored token.
module "health" {
  source = "../modules/health"

  project_id   = var.project_id
  environment  = var.environment
  service_name = var.service_name

  # NOTE: Terraform-created uptime checks may fail due to monitored resource
  # validation and org policy. Create uptime checks via gcloud script instead.
  enable_checks = false

  # Full service URLs (used by module inputs that expect URL)
  backend_url  = "https://nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app"
  frontend_url = "https://nexus-shield-portal-frontend-2tqp6t4txq-uc.a.run.app"

  # Hostnames (no scheme) for uptime checks
  backend_host  = "nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app"
  frontend_host = "nexus-shield-portal-frontend-2tqp6t4txq-uc.a.run.app"

  auth_headers = {
    Authorization = "Bearer ${random_password.uptime_token.result}"
  }
}

# COMPLIANCE MODULE - DEFERRED TO PHASE 4.2 (IAM group creation needed)
# module "compliance" {
#   source = "../modules/compliance"
#
#   project_id   = var.project_id
#   environment  = var.environment
#   service_name = var.service_name
#   labels       = var.labels
# }
#
# HEALTH MODULE - DEFERRED TO PHASE 4.2 (resource_group validation + URL configuration)
# module "health" {
#   source = "../modules/health"
#
#   project_id   = var.project_id
#   environment  = var.environment
#   service_name = var.service_name
#   backend_url  = ""
#   frontend_url = ""
# }
