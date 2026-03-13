/*
  Terraform: Cloud Build Triggers for Direct Deployment
  Purpose: Create Cloud Build triggers for policy-check and direct-deploy pipelines
  
  These triggers are designed to work with the webhook receiver fallback since
  GitHub OAuth connection is not yet available. Triggers can be invoked via:
  1. Cloud Build API (programmatically from webhook receiver)
  2. Cloud Scheduler (for scheduled jobs)
  3. Eventually native GitHub connection (once OAuth is completed)
*/

# ---------------------------------------------------------------------------
# Policy Check Trigger (Cloud Build)
# NOTE: Commented out pending manual GitHub OAuth connection in Cloud Build console
# This can be applied after completing Cloud Build → GitHub connection in Google Cloud console
# URL: https://console.cloud.google.com/cloud-build/triggers
# ---------------------------------------------------------------------------
/*
resource "google_cloudbuild_trigger" "policy_check_trigger" {
  project = var.project_id
  name    = "policy-check-trigger"
  description = "FAANG Governance: Validate commits against policy standards"

  # Use github as the trigger source (will work once connection exists)
  # For now, this trigger can be manually invoked or called via Cloud Build API
  github {
    owner = "kushin77"
    name  = "self-hosted-runner"
    push {
      branch = "^main$"
    }
  }

  # Reference the policy check build config
  filename = "cloudbuild.policy-check.yaml"

  # Use prod-deployer service account
  service_account = "projects/${var.project_id}/serviceAccounts/${var.prod_deployer_sa_email}"

  # Tags for organization and filtering
  tags = ["governance", "policy-check", "production"]

  # Don't block on create if GitHub connection missing
  substitutions = {
    "_POLICY_BUCKET" = "gs://nexusshield-policy"
    "_NOTIFY_EMAIL"  = "ops@example.com"
  }

  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"
}
*/

# ---------------------------------------------------------------------------
# Direct Deploy Trigger (Cloud Build)
# NOTE: Commented out pending manual GitHub OAuth connection in Cloud Build console
# This can be applied after completing Cloud Build → GitHub connection in Google Cloud console
# URL: https://console.cloud.google.com/cloud-build/triggers
# ---------------------------------------------------------------------------
/*
resource "google_cloudbuild_trigger" "direct_deploy_trigger" {
  project = var.project_id
  name    = "direct-deploy-trigger"
  description = "FAANG Governance: Direct deployment from main branch (no release workflow)"

  # Use github as the trigger source (will work once connection exists)
  github {
    owner = "kushin77"
    name  = "self-hosted-runner"
    push {
      branch = "^main$"
    }
  }

  # Reference the direct deploy build config
  filename = "cloudbuild.yaml"

  # Use prod-deployer service account
  service_account = "projects/${var.project_id}/serviceAccounts/${var.prod_deployer_sa_email}"

  # Tags for organization and filtering
  tags = ["direct-deploy", "production", "no-release"]

  # Substitutions for deployment parameters
  substitutions = {
    "_SBOM_BUCKET"     = "gs://nexusshield-sbom"
    "_COSIGN_KMS_URI"  = "projects/${var.project_id}/locations/global/keyRings/cosign/cryptoKeys/cosign"
    "_DEPLOY_REGION"   = "us-central1"
  }

  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"
}
*/

# ---------------------------------------------------------------------------
# Grant Cloud Build service account access to Cloud Run deployment
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_run_deployer" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# Grant Cloud Build service account access to Secret Manager
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# Grant Cloud Build service account access to Cloud KMS
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_kms_user" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# Grant Cloud Build service account artifact registry writer
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# Outputs for webhook receiver and other integrations
# NOTE: Commented out - resources pending GitHub OAuth connection
# ---------------------------------------------------------------------------
/*
output "policy_check_trigger_id" {
  description = "Policy check trigger ID for webhook invocation"
  value       = google_cloudbuild_trigger.policy_check_trigger.id
}

output "direct_deploy_trigger_id" {
  description = "Direct deploy trigger ID for webhook invocation"
  value       = google_cloudbuild_trigger.direct_deploy_trigger.id
}

output "policy_check_trigger_name" {
  description = "Policy check trigger name"
  value       = google_cloudbuild_trigger.policy_check_trigger.name
}

output "direct_deploy_trigger_name" {
  description = "Direct deploy trigger name"
  value       = google_cloudbuild_trigger.direct_deploy_trigger.name
}
*/
