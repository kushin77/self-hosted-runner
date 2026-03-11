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

# Secret Manager secrets for all service credentials
# These should be manually created and populated with actual values via gcloud CLI

resource "google_secret_manager_secret" "backend_db" {
  secret_id = "backend-db-secret"
  labels = {
    service = "backend"
    env     = "production"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret" "backend_auth" {
  secret_id = "backend-auth-secret"
  labels = {
    service = "backend"
    env     = "production"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret" "image_pin_api" {
  secret_id = "image-pin-authn"
  labels = {
    service = "image-pin-service"
    env     = "production"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret" "github_deploy" {
  secret_id = "github-deploy-authn"
  labels = {
    service = "deployment"
    env     = "production"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret" "gcp_service_account" {
  secret_id = "gcp-cloud-run-authn"
  labels = {
    service = "deployment"
    env     = "production"
  }
  replication {
    automatic = true
  }
}

# IAM binding: Allow Cloud Run service account to read secrets
resource "google_secret_manager_secret_iam_binding" "backend_db_access" {
  secret_id = google_secret_manager_secret.backend_db.id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${var.cloud_run_sa_email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "backend_auth_access" {
  secret_id = google_secret_manager_secret.backend_auth.id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${var.cloud_run_sa_email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "image_pin_api_access" {
  secret_id = google_secret_manager_secret.image_pin_api.id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${var.cloud_run_sa_email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "github_deploy_access" {
  secret_id = google_secret_manager_secret.github_deploy.id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${var.cloud_run_sa_email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "gcp_service_account_access" {
  secret_id = google_secret_manager_secret.gcp_service_account.id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${var.cloud_run_sa_email}"
  ]
}

# Output secret names for reference in deployment
output "secrets" {
  value = {
    backend_db             = google_secret_manager_secret.backend_db.id
    backend_auth           = google_secret_manager_secret.backend_auth.id
    image_pin_api          = google_secret_manager_secret.image_pin_api.id
    github_deploy          = google_secret_manager_secret.github_deploy.id
    gcp_service_account    = google_secret_manager_secret.gcp_service_account.id
  }
  description = "Secret Manager secret IDs for production services"
}
