# GCP Workload Identity Federation setup for GitHub OIDC
# Purpose: Enable GitHub Actions to authenticate to GCP using OIDC tokens
# No long-lived service account keys needed; tokens auto-expire

# Enable required APIs
resource "google_project_service" "iam_api" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts_api" {
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials_api" {
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager_api" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub OIDC"
  disabled                  = false
}

# Workload Identity Provider for GitHub
resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions Provider"
  description                        = "GitHub OIDC provider for Actions"
  disabled                           = false

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.aud"        = "assertion.aud"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account for secrets orchestration
resource "google_service_account" "secrets_orchestrator" {
  account_id   = "secrets-orchestrator"
  display_name = "Secrets Orchestration Service Account"
  description  = "Service account for multi-layer secrets orchestration"
}

# Workload Identity binding
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.secrets_orchestrator.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/kushin77/self-hosted-runner"
}

# Grant Secret Manager Accessor role (to read secrets from GSM)
resource "google_project_iam_member" "secrets_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.secrets_orchestrator.email}"
}

# Grant Cloud Run Developer (for deployment)
resource "google_project_iam_member" "cloudrun_developer" {
  project = var.gcp_project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.secrets_orchestrator.email}"
}

# Grant Cloud Scheduler Job Runner
resource "google_project_iam_member" "scheduler_runner" {
  project = var.gcp_project_id
  role    = "roles/cloudscheduler.jobRunner"
  member  = "serviceAccount:${google_service_account.secrets_orchestrator.email}"
}

# Outputs
output "gcp_project_id" {
  value = var.gcp_project_id
}

output "gcp_wif_provider" {
  value       = google_iam_workload_identity_pool_provider.github_actions.name
  description = "Workload Identity Provider resource name"
}

output "gcp_orch_sa_email" {
  value       = google_service_account.secrets_orchestrator.email
  description = "Service account email for secrets orchestration"
}
