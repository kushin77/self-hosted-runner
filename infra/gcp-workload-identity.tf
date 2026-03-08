# GCP Workload Identity Federation setup for GitHub Actions
# Enables ephemeral OIDC-based authentication (no long-lived service account keys)

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "github_repo_owner" {
  description = "GitHub repository owner (username or org)"
  type        = string
  default     = "kushin77"
}

variable "github_repo_name" {
  description = "GitHub repository name"
  type        = string
  default     = "self-hosted-runner"
}

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  project                   = var.gcp_project_id
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions OIDC"
  disabled                  = false
}

# OIDC Provider
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  project                            = var.gcp_project_id
  display_name                       = "GitHub OIDC Provider"
  disabled                           = false

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service Account for secrets access
resource "google_service_account" "github_secrets" {
  account_id   = "github-secrets-sa"
  display_name = "GitHub Secrets Service Account"
}

# GSM admin role
resource "google_project_iam_member" "gsm_admin" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.github_secrets.email}"
}

# Data source for project info
data "google_client_config" "current" {}

data "google_projects" "project" {
  filter = "projectId:${var.gcp_project_id}"
}

output "gcp_workload_identity_provider" {
  value = "projects/${data.google_projects.project.projects[0].number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_provider.workload_identity_pool_provider_id}"
}
