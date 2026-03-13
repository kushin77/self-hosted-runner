/*
  Terraform: org_admin/main.tf
  Purpose: Provide reviewable, ready-to-apply Terraform resources for org admins
  - Project-level IAM bindings for service accounts
  - Service enablement helpers
  - KMS & Secret Manager IAM bindings

  NOTE: This module is intentionally *not* applied by CI. Org admins should
  review and run `terraform plan` + `terraform apply` from a privileged host
  with sufficient org-level permissions.
*/

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

# ---------------------------------------------------------------------------
# 1) Grant `roles/iam.serviceAccountAdmin` to `prod-deployer-sa`
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "prod_deployer_sa_service_account_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${var.prod_deployer_sa_email}"
  # Note: consider using google_project_iam_binding if you need to manage the
  # full set of members rather than a single member.
}

# ---------------------------------------------------------------------------
# 2) Grant `roles/iam.serviceAccounts.create` to Cloud Build SA
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_serviceaccounts_create" {
  project = var.project_id
  role    = "roles/iam.serviceAccounts.create"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# 7) Allow Cloud Build SA to impersonate the deployer SA
# ---------------------------------------------------------------------------
resource "google_service_account_iam_member" "cloud_build_impersonate_deployer" {
  service_account_id = var.prod_deployer_sa_email
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# 8) Secret Manager access: grant `roles/secretmanager.secretAccessor` to
#    service accounts used by Cloud Run / Cloud Run services.
#    This will create project-level bindings; for resource-level binding use
#    google_secret_manager_secret_iam_member resources instead.
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "secretmanager_accessor_backend" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.backend_sa_email}"
}

resource "google_project_iam_member" "secretmanager_accessor_frontend" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.frontend_sa_email}"
}

# ---------------------------------------------------------------------------
# 10) Enable required APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "enable_secretmanager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"
}

resource "google_project_service" "enable_cloudbuild" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "enable_cloudkms" {
  project = var.project_id
  service = "cloudkms.googleapis.com"
}

resource "google_project_service" "enable_cloudscheduler" {
  project = var.project_id
  service = "cloudscheduler.googleapis.com"
}

resource "google_project_service" "enable_pubsub" {
  project = var.project_id
  service = "pubsub.googleapis.com"
}

# ---------------------------------------------------------------------------
# 12) KMS key access: grant `roles/cloudkms.cryptoKeyEncrypterDecrypter`
# ---------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "kms_decrypter_backend" {
  crypto_key_id = var.kms_crypto_key_resource_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.backend_sa_email}"
}

# ---------------------------------------------------------------------------
# 11) Cloud Scheduler permissions: grant scheduler invoker to the scheduler SA
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_scheduler_invoker" {
  project = var.project_id
  role    = "roles/cloudscheduler.serviceAgent"
  member  = "serviceAccount:${var.cloud_scheduler_sa_email}"
}

# ---------------------------------------------------------------------------
# 13) Pub/Sub topic IAM placeholder: create binding for milestone organizer
# ---------------------------------------------------------------------------
# Note: We create a project-level Pub/Sub IAM binding (topic-level preferred).
resource "google_project_iam_member" "pubsub_publisher_milestone" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.milestone_sa_email}"
}

# ---------------------------------------------------------------------------
# 9) VPC-SC exceptions and org policies cannot be applied by project-level
#    Terraform without org-level credentials. Provide sample org_policy
#    resources below in comments for org admins to consider.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 3/4/6/14 - Org-level items that require org admin manual approval:
#  - Cloud SQL org policy exceptions (3 & 4)
#  - S3 ObjectLock for AWS bucket (6) [AWS side]
#  - Service account allowlist for worker SSH (14)
#
# These are documented in README.md with the commands and sample Terraform
# snippets that org admins can apply in their org-level workspace.
# ---------------------------------------------------------------------------

output "note_manual_steps" {
  value = "Some items require org-level approval and are documented in README.md. Review before apply."
}
