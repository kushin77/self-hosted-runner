terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Service account for Cloud Run services (to be attached to Cloud Run revisions)
resource "google_service_account" "run_sa" {
  account_id   = "nexusshield-run-sa"
  display_name = "NexusShield Cloud Run service account"
}

# Service account for scheduler to call the image-pin service
resource "google_service_account" "scheduler_sa" {
  account_id   = "nexusshield-scheduler-sa"
  display_name = "Scheduler service account for image-pin"
}

# Allow scheduler SA to invoke Cloud Run services (roles/run.invoker)
resource "google_project_iam_member" "scheduler_invoke" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# Bind the created run SA with minimal roles (example: run.runtimeServiceAccount + secret access)
resource "google_project_iam_member" "run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}
