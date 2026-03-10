variable "project" {
  type        = string
  description = "GCP project id where the Secret Manager API will be enabled"
}

resource "google_project_service" "secretmanager" {
  project = var.project
  service = "secretmanager.googleapis.com"

  # Keep the service enabled; do not disable on destroy to avoid outages.
  disable_dependent_services_on_destroy = false
}
