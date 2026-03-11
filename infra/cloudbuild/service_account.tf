resource "google_service_account" "bootstrap_sa" {
  account_id   = "gov-bootstrap-sa"
  display_name = "Governance Bootstrap Service Account"
}

resource "google_project_iam_member" "bootstrap_cloudbuild_admin" {
  project = var.project
  role    = "roles/cloudbuild.admin"
  member  = "serviceAccount:${google_service_account.bootstrap_sa.email}"
}

resource "google_project_iam_member" "bootstrap_secret_accessor" {
  project = var.project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.bootstrap_sa.email}"
}
