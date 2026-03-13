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
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

provider "github" {
  # Token from environment: GITHUB_TOKEN
  owner = var.github_org
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
# 1b) Grant Cloud Run deployer role to prod-deployer-sa
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "prod_deployer_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${var.prod_deployer_sa_email}"
}

# ---------------------------------------------------------------------------
# 1c) Grant Compute Admin role to prod-deployer-sa for direct deployment
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "prod_deployer_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${var.prod_deployer_sa_email}"
}

# ---------------------------------------------------------------------------
# 1d) Grant KMS and Secret Manager access to prod-deployer-sa
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "prod_deployer_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.prod_deployer_sa_email}"
}

resource "google_project_iam_member" "prod_deployer_kms_user" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${var.prod_deployer_sa_email}"
}

# ---------------------------------------------------------------------------
# 2) Grant `roles/iam.serviceAccounts.create` to Cloud Build SA
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_serviceaccounts_create" {
  project = var.project_id
  role    = "roles/iam.serviceAccountCreator"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# 2b) Grant Cloud Build necessary roles for direct deployment pipeline
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_build_editor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

resource "google_project_iam_member" "cloud_build_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

resource "google_project_iam_member" "cloud_build_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.cloud_build_sa_email}"
}

# ---------------------------------------------------------------------------
# 7) Allow Cloud Build SA to impersonate the deployer SA
# ---------------------------------------------------------------------------
resource "google_service_account_iam_member" "cloud_build_impersonate_deployer" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.prod_deployer_sa_email}"
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
# Resource-level Secret Manager IAM examples (preferred for least-privilege)
# Use these examples to grant access to a specific secret rather than the
# whole project. Org admins should adapt `secret_id` to point to the exact
# secret resource (recommended) or use the full resource path.
# ---------------------------------------------------------------------------
# Example: grant `secretAccessor` to the backend service account for a single
# secret named `my-backend-secret`. Replace `my-backend-secret` with the
# actual secret id in your project.
# COMMENTED OUT: Backend already has project-level secret accessor role.
# Uncomment and update secret_id to apply this for a specific secret.
# resource "google_secret_manager_secret_iam_member" "backend_secret_accessor" {
#   secret_id = "projects/${var.project_id}/secrets/my-backend-secret"
#   role      = "roles/secretmanager.secretAccessor"
#   member    = "serviceAccount:${var.backend_sa_email}"
# }

# Example: if you prefer referencing an existing secret resource created in
# Terraform, use the secret resource reference instead of the string path:
#
# resource "google_secret_manager_secret" "example" {
#   secret_id = "my-backend-secret"
#   replication { automatic = true }
# }
#
# resource "google_secret_manager_secret_iam_member" "backend_secret_accessor_ref" {
#   secret_id = google_secret_manager_secret.example.id
#   role      = "roles/secretmanager.secretAccessor"
#   member    = "serviceAccount:${var.backend_sa_email}"
# }


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
# 11) Cloud Scheduler permissions: grant scheduler invoker & pubsub publisher
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "cloud_scheduler_invoker" {
  project = var.project_id
  role    = "roles/cloudscheduler.serviceAgent"
  member  = "serviceAccount:${var.cloud_scheduler_sa_email}"
}

resource "google_project_iam_member" "cloud_scheduler_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.cloud_scheduler_sa_email}"
}

resource "google_project_iam_member" "cloud_scheduler_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${var.cloud_scheduler_sa_email}"
}

# ---------------------------------------------------------------------------
# 13) Pub/Sub topic IAM: grant publisher role for milestone organizer
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "pubsub_publisher_milestone" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.milestone_sa_email}"
}

resource "google_project_iam_member" "pubsub_subscriber_milestone" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${var.milestone_sa_email}"
}

# ---------------------------------------------------------------------------
# 13b) Add Secret Manager and KMS access for milestone organizer
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "milestone_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.milestone_sa_email}"
}

# ---------------------------------------------------------------------------
# 3/4/6/14 - ORG-LEVEL ITEMS REQUIRING MANUAL APPROVAL
# ---------------------------------------------------------------------------
# The following items require org-level credentials and must be applied 
# by GCP organization admins in a separate org-level Terraform workspace.
# 
# ITEM 3: Approve Cloud SQL org policy exception for production
#   Command: gcloud org-policies delete sql.restrictPublicIp --project=nexusshield-prod
#   Or create exception in Cloud Console: 
#   https://console.cloud.google.com/iam-admin/orgpolicies
#
# ITEM 4: Approve Cloud SQL org policy exception for staging
#   Command: gcloud org-policies delete sql.restrictPublicIp --project=nexusshield-staging
#
# ITEM 6: Approve S3 ObjectLock for compliance bucket retention (AWS side)
#   Command (on AWS): aws s3api put-bucket-object-lock-configuration \
#     --bucket nexusshield-prod-immutable-logs \
#     --object-lock-configuration 'ObjectLockEnabled=Enabled,Rule={DefaultRetention={Mode=COMPLIANCE,Days=365}}'
#   This MUST be done before the bucket is created or modified.
#
# ITEM 14: Confirm service account allowlist changes for worker SSH access
#   - Add 'prod-deployer-sa@nexusshield-prod.iam.gserviceaccount.com' to 
#     the allowlist for GCE instance metadata SSH key uploads
#   - Verify in Cloud Console: Compute Engine > Settings > Service Accounts
#
# These require org-admin review and approval. Once complete, update this
# file to reflect completion and re-run: terraform plan && terraform apply
# ---------------------------------------------------------------------------

output "checklist_org_items" {
  value = {
    item_3  = "Cloud SQL org policy exception for production"
    item_4  = "Cloud SQL org policy exception for staging"
    item_6  = "AWS S3 ObjectLock compliance bucket encryption"
    item_14 = "Service account allowlist for worker SSH access"
  }
  description = "Org-level items requiring manual approval. See comments in main.tf"
}

output "note_manual_steps" {
  value = "ORG-LEVEL ITEMS: 3, 4, 6, 14 require org admin approval. See output.checklist_org_items above."
}
