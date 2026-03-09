terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {}

resource "google_service_account" "runner_sa" {
  project      = var.project
  account_id   = var.service_account_id
  display_name = var.display_name
}

resource "google_project_iam_member" "sa_roles" {
  for_each = toset(var.roles)
  project  = var.project
  role     = each.key
  member   = "serviceAccount:${google_service_account.runner_sa.email}"
}
