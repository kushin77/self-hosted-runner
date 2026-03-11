variable "project" {
  type = string
}

variable "deploy_sa_name" {
  type    = string
  default = "sa-deploy-synthetic"
}

resource "google_service_account" "deploy_sa" {
  account_id   = var.deploy_sa_name
  display_name = "Deploy synthetic checker SA"
  project      = var.project
}

# Grant minimal roles to the deploy SA for deployment actions
resource "google_project_iam_member" "deploy_sa_cloudfunctions" {
  project = var.project
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
}

resource "google_project_iam_member" "deploy_sa_pubsub" {
  project = var.project
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
}

resource "google_project_iam_member" "deploy_sa_scheduler" {
  project = var.project
  role    = "roles/cloudscheduler.admin"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
}

# Create an empty Secret Manager secret resource to hold the deploy key (admin will add a version)
resource "google_secret_manager_secret" "deploy_sa_key" {
  project = var.project
  secret_id = "deploy-sa-key"
  replication {
    automatic = true
  }
}

output "deploy_sa_email" {
  value = google_service_account.deploy_sa.email
}

output "deploy_secret_name" {
  value = google_secret_manager_secret.deploy_sa_key.name
}
