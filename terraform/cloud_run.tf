variable "cloudrun_image" {
  description = "Container image for the automation Cloud Run service"
  type        = string
  default     = ""
}

variable "cloudrun_service_account" {
  description = "Service account email used by Cloud Run service"
  type        = string
  default     = ""
}

resource "google_service_account" "cloudrun_sa" {
  count        = var.cloudrun_service_account == "" ? 1 : 0
  account_id   = "automation-runner-sa-${lower(random_string.run_id.result)}"
  display_name = "Automation Runner Service Account"
}

resource "random_string" "run_id" {
  length  = 6
  special = false
}

resource "google_cloud_run_service" "automation" {
  name     = "automation-runner"
  location = var.gcp_region

  template {
    spec {
      containers {
        image = var.cloudrun_image
        env {}
      }
      service_account_name = var.cloudrun_service_account != "" ? var.cloudrun_service_account : google_service_account.cloudrun_sa[0].email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

// Note: Pub/Sub push subscriptions are intentionally left out to avoid
// tight coupling; operators can create push subscriptions pointing to
// the Cloud Run service URL (see docs/CLOUD_SCHEDULER.md).

output "cloudrun_url" {
  value = google_cloud_run_service.automation.status[0].url
}
