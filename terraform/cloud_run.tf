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

variable "vault_role_id_secret_name" {
  description = "Secret Manager secret name (not full path) that stores Vault AppRole role_id"
  type        = string
  default     = ""
}

variable "vault_secret_id_secret_name" {
  description = "Secret Manager secret name that stores Vault AppRole secret_id"
  type        = string
  default     = ""
}

variable "vault_addr" {
  description = "Address of the Vault server (eg: https://vault.example.com)"
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
        env {
          name  = "PROJECT"
          value = var.gcp_project
        }
        env {
          name  = "VAULT_ADDR"
          value = var.vault_addr
        }

        # Map Vault AppRole credentials from Secret Manager into container env vars
        env {
          name = "VAULT_ROLE_ID"
          value_from {
            secret_key_ref {
              name = var.vault_role_id_secret_name
              key  = "latest"
            }
          }
        }

        env {
          name = "VAULT_SECRET_ID"
          value_from {
            secret_key_ref {
              name = var.vault_secret_id_secret_name
              key  = "latest"
            }
          }
        }
      }
      service_account_name = var.cloudrun_service_account != "" ? var.cloudrun_service_account : google_service_account.cloudrun_sa[0].email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

// Grant the Cloud Run service account access to read the Vault AppRole secrets
resource "google_secret_manager_secret_iam_member" "vault_role_accessor" {
  count   = var.vault_role_id_secret_name != "" ? 1 : 0
  project = var.gcp_project
  secret_id = var.vault_role_id_secret_name
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.cloudrun_service_account != "" ? var.cloudrun_service_account : google_service_account.cloudrun_sa[0].email}"
}

resource "google_secret_manager_secret_iam_member" "vault_secret_accessor" {
  count   = var.vault_secret_id_secret_name != "" ? 1 : 0
  project = var.gcp_project
  secret_id = var.vault_secret_id_secret_name
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.cloudrun_service_account != "" ? var.cloudrun_service_account : google_service_account.cloudrun_sa[0].email}"
}

// Note: Pub/Sub push subscriptions are intentionally left out to avoid
// tight coupling; operators can create push subscriptions pointing to
// the Cloud Run service URL (see docs/CLOUD_SCHEDULER.md).

// Portal backend service (deployed via Cloud Build and imported)
resource "google_cloud_run_service" "backend" {
  name     = "nexus-shield-portal-backend"
  location = var.gcp_region
  
  # Imported from manual deployment via Cloud Build
  # To import: terraform import google_cloud_run_service.backend "locations/us-central1/namespaces/nexusshield-prod/services/nexus-shield-portal-backend"
}

// Portal frontend service (deployed via Cloud Build and imported)
resource "google_cloud_run_service" "frontend" {
  name     = "nexus-shield-portal-frontend"
  location = var.gcp_region
  
  # Imported from manual deployment via Cloud Build
  # To import: terraform import google_cloud_run_service.frontend "locations/us-central1/namespaces/nexusshield-prod/services/nexus-shield-portal-frontend"
}

output "cloudrun_url" {
  value = google_cloud_run_service.automation.status[0].url
}

output "backend_url" {
  value = google_cloud_run_service.backend.status[0].url
}

output "frontend_url" {
  value = google_cloud_run_service.frontend.status[0].url
}
