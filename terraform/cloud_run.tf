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
  count      = var.cloudrun_service_account == "" ? 1 : 0
  account_id = "automation-runner-sa-${random_string.run_id.result}"
  display_name = "Automation Runner Service Account"
}

resource "random_string" "run_id" {
  length = 6
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

  traffics {
    percent = 100
    latest_revision = true
  }
}

resource "google_pubsub_subscription" "vault_push_sub" {
  name  = "vault-sync-sub"
  topic = google_pubsub_topic.vault_sync.name

  push_config {
    push_endpoint = "https://${google_cloud_run_service.automation.status[0].url}/"
    oidc_token {
      service_account_email = var.cloudrun_service_account != "" ? var.cloudrun_service_account : google_service_account.cloudrun_sa[0].email
    }
  }
}

resource "google_pubsub_subscription" "cleanup_push_sub" {
  name  = "ephemeral-cleanup-sub"
  topic = google_pubsub_topic.ephemeral_cleanup.name

  push_config {
    push_endpoint = "https://${google_cloud_run_service.automation.status[0].url}/"
    oidc_token {
      service_account_email = var.cloudrun_service_account != "" ? var.cloudrun_service_account : google_service_account.cloudrun_sa[0].email
    }
  }
}

output "cloudrun_url" {
  value = google_cloud_run_service.automation.status[0].url
}
