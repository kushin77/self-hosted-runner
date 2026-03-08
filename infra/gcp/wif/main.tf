terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_iam_workload_identity_pool" "github_actions_pool" {
  provider = google
  project  = var.project_id
  location = "global"
  workload_identity_pool_id = var.pool_id
  display_name = "GitHub Actions WIP"
}

resource "google_iam_workload_identity_pool_provider" "github_actions_provider" {
  provider = google
  project  = var.project_id
  location = "global"
  workload_identity_pool_id = google_iam_workload_identity_pool.github_actions_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name = "GitHub Actions Provider"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  # Map OIDC assertion fields to GCP attributes. Use attribute.* for custom attributes.
  attribute_mapping = {
    "google.subject"     = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"      = "assertion.ref"
    "attribute.actor"    = "assertion.actor"
  }
}
