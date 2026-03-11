/**
 * IAM Module - Main Configuration
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
# SERVICE ACCOUNTS
# ============================================================================

/**
 * Backend Service Account
 * Used by Cloud Run backend container
 * Permissions: Cloud SQL Proxy, Secret Manager read, Cloud Logging
 */
resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "${var.service_name}-backend-${var.environment}"
  display_name = "Backend Service Account - ${var.environment}"
  description  = "Service account for NexusShield backend deployment"

}

/**
 * Frontend Service Account
 * Used by Cloud Run frontend container
 * Permissions: Cloud Storage (assets), Cloud Logging
 */
resource "google_service_account" "frontend" {
  project      = var.project_id
  account_id   = "${var.service_name}-frontend-${var.environment}"
  display_name = "Frontend Service Account - ${var.environment}"
  description  = "Service account for NexusShield frontend deployment"

}

/**
 * Terraform Deployment Service Account
 * Used by Terraform CLI to manage infrastructure
 * Permissions: Editor (broad, for IaC management)
 */
resource "google_service_account" "terraform" {
  project      = var.project_id
  account_id   = "${var.service_name}-terraform-${var.environment}"
  display_name = "Terraform Service Account - ${var.environment}"
  description  = "Service account for Terraform infrastructure management"

}

# ============================================================================
# CUSTOM ROLES
# ============================================================================

/**
 * Custom role for Cloud SQL Proxy access
 * Minimal permissions to connect to database via private IP
 */
resource "google_project_iam_custom_role" "cloud_sql_proxy" {
  project     = var.project_id
  role_id     = "${replace(var.service_name, "-", "_")}_cloud_sql_proxy_${var.environment}"
  title       = "Cloud SQL Proxy Role - ${var.environment}"
  description = "Minimal role for Cloud SQL Proxy connections"

  permissions = [
    "cloudsql.instances.connect",
    "cloudsql.instances.get",
  ]
}

/**
 * Custom role for Secret Manager read-only access
 * Allow reading application secrets
 */
resource "google_project_iam_custom_role" "secret_reader" {
  project     = var.project_id
  role_id     = "${replace(var.service_name, "-", "_")}_secret_reader_${var.environment}"
  title       = "Secret Reader Role - ${var.environment}"
  description = "Read-only access to application secrets"

  permissions = [
    "secretmanager.secrets.get",
    "secretmanager.versions.access",
    "resourcemanager.projects.get",
  ]
}

# ============================================================================
# IAM ROLE BINDINGS
# ============================================================================

# Backend Service Account Roles
resource "google_project_iam_member" "backend_cloud_sql_proxy" {
  project = var.project_id
  role    = google_project_iam_custom_role.cloud_sql_proxy.id
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_project_iam_member" "backend_secret_reader" {
  project = var.project_id
  role    = google_project_iam_custom_role.secret_reader.id
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_project_iam_member" "backend_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_project_iam_member" "backend_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# Frontend Service Account Roles
resource "google_project_iam_member" "frontend_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.frontend.email}"
}

resource "google_project_iam_member" "frontend_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.frontend.email}"
}

# Terraform Service Account Roles
resource "google_project_iam_member" "terraform_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# ============================================================================
# WORKLOAD IDENTITY (Optional - for GitHub Actions)
# ============================================================================

resource "google_iam_workload_identity_pool" "github" {
  count                     = var.enable_workload_identity && var.github_repo != "" ? 1 : 0
  project                   = var.project_id
  workload_identity_pool_id = "${replace(var.service_name, "-", "_")}_github_${var.environment}"
  # location removed for provider compatibility
  display_name = "GitHub Workload Identity - ${var.environment}"
  description  = "Workload Identity for GitHub Actions"
  disabled     = false
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count                              = var.enable_workload_identity && var.github_repo != "" ? 1 : 0
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "${replace(var.service_name, "-", "_")}_github_provider_${var.environment}"
  # location removed for provider compatibility
  display_name = "GitHub Provider - ${var.environment}"
  disabled     = false

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account impersonation for GitHub Actions
resource "google_service_account_iam_member" "github_impersonate_terraform" {
  count              = var.enable_workload_identity && var.github_repo != "" ? 1 : 0
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github[0].workload_identity_pool_id}/attribute.repository/${var.github_repo}"
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "google_project" "current" {
  project_id = var.project_id
}
