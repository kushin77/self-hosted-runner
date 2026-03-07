terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

resource "google_iam_workload_identity_pool" "github_pool" {
  provider = google
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions Workload Identity Pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  provider = google
  workload_identity_pool_id = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name = "GitHub Actions OIDC Provider"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_binding" "sa_workload_user" {
  service_account_id = var.service_account_email
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_org}/${var.github_repo}"
  ]
}

output "provider_full_name" {
  value = google_iam_workload_identity_pool_provider.github_provider.name
}
