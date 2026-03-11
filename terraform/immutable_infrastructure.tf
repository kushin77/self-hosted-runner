// ============================================================================
// IMMUTABLE INFRASTRUCTURE AUTOMATION
// ============================================================================
// This module ensures immutable, ephemeral, idempotent infrastructure deployments
// without manual intervention. All resources are:
// - Created fresh on each deployment
// - Cleaned up automatically
// - Versioned and pinned
// - Managed entirely through Terraform state
// - Zero-touch, hands-off operations
// ============================================================================

// ============================================================================
// RESOURCE VERSION PINNING & IMAGE MANAGEMENT
// ============================================================================

// Immutable image registry with SHA256 pinning
resource "google_storage_bucket" "image_pin_registry" {
  name     = "${local.env_prefix}-image-pin-registry"
  project  = var.gcp_project
  location = "US"

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = false // Allow cleanup
  }
}

// Immutable deployment manifest storage
resource "google_storage_bucket" "deployment_manifests" {
  name     = "${local.env_prefix}-deployment-manifests"
  project  = var.gcp_project
  location = "US"

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  object_retention {
    mode         = "Locked" // Immutable once written
    retain_until_ms = 86400000 // 24 hours
  }

  lifecycle {
    prevent_destroy = false
  }
}

// ============================================================================
// EPHEMERAL RESOURCE LIFECYCLE MANAGEMENT
// ============================================================================

// Pub/Sub topic for triggering ephemeral resource cleanup
resource "google_pubsub_topic" "ephemeral_resource_cleanup" {
  name    = "${local.env_prefix}-ephemeral-cleanup"
  project = var.gcp_project
}

// Dead letter topic for cleanup failures
resource "google_pubsub_topic" "cleanup_dlq" {
  name    = "${local.env_prefix}-cleanup-dlq"
  project = var.gcp_project
}

// Cloud Scheduler job to trigger ephemeral cleanup every 6 hours
resource "google_cloud_scheduler_job" "ephemeral_cleanup_job" {
  name             = "${local.env_prefix}-ephemeral-cleanup-6h"
  description      = "Automatic ephemeral resource cleanup - idempotent and hands-off"
  schedule         = "0 */6 * * *" // Every 6 hours
  time_zone        = "UTC"
  attempt_deadline = "320s"
  region           = var.gcp_region
  project          = var.gcp_project

  pubsub_target {
    topic_name = google_pubsub_topic.ephemeral_resource_cleanup.id
    data       = base64encode(jsonencode({
      action = "cleanup-ephemeral"
      timestamp = timestamp()
    }))
  }

  retry_config {
    retry_count = 1
  }
}

// Cloud Function for idempotent ephemeral cleanup
resource "google_storage_bucket" "cleanup_function_source" {
  name     = "${local.env_prefix}-cleanup-function-src"
  project  = var.gcp_project
  location = "US"

  lifecycle {
    prevent_destroy = false
  }
}

// Cleanup function code
data "archive_file" "cleanup_function_code" {
  type        = "zip"
  output_path = "/tmp/cleanup_function.zip"
  source_dir  = "${path.module}/../scripts/cloud_functions/ephemeral_cleanup"
}

resource "google_storage_bucket_object" "cleanup_function_zip" {
  name   = "cleanup-function-${data.archive_file.cleanup_function_code.output_base64sha256}.zip"
  bucket = google_storage_bucket.cleanup_function_source.name
  source = data.archive_file.cleanup_function_code.output_path
}

resource "google_cloudfunctions_function" "ephemeral_cleanup" {
  name            = "${local.env_prefix}-ephemeral-cleanup-fn"
  runtime         = "python39"
  project         = var.gcp_project
  region          = var.gcp_region
  available_memory_mb = 256
  timeout         = 300
  source_archive_bucket = google_storage_bucket.cleanup_function_source.name
  source_archive_object = google_storage_bucket_object.cleanup_function_zip.name
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.ephemeral_resource_cleanup.id
  }
  entry_point = "cleanup_ephemeral_resources"

  environment_variables = {
    ENVIRONMENT = var.environment
    GCP_PROJECT = var.gcp_project
    GCP_REGION  = var.gcp_region
  }

  service_account_email = google_service_account.automation_sa.email
}

// ============================================================================
// AUTOMATED STATE MANAGEMENT & VERSIONING
// ============================================================================

// State backup to GCS (immutable versions)
resource "google_storage_bucket" "terraform_state_backup" {
  name     = "${local.env_prefix}-terraform-state-backup"
  project  = var.gcp_project
  location = "US"

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  // Automatic deletion of old versions after 90 days
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 20
      days_since_noncurrent_time = 90
    }
  }
}

// ============================================================================
// AUTOMATION SERVICE ACCOUNT & WORKLOAD IDENTITY
// ============================================================================

resource "google_service_account" "automation_sa" {
  account_id   = "${local.env_prefix}-automation"
  display_name = "Automation Service Account for ${var.environment}"
  project      = var.gcp_project
}

// Roles for immutable, automated deployment
resource "google_project_iam_member" "automation_cloud_run_admin" {
  project = var.gcp_project
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.automation_sa.email}"
}

resource "google_project_iam_member" "automation_kms_user" {
  project = var.gcp_project
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.automation_sa.email}"
}

resource "google_project_iam_member" "automation_secrets_access" {
  project = var.gcp_project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.automation_sa.email}"
}

resource "google_project_iam_member" "automation_artifact_registry" {
  project = var.gcp_project
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${google_service_account.automation_sa.email}"
}

resource "google_project_iam_member" "automation_cloud_build" {
  project = var.gcp_project
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.automation_sa.email}"
}

// ============================================================================
// DIRECT DEPLOYMENT WEBHOOK & AUTOMATION TRIGGER
// ============================================================================

// Pub/Sub topic for direct deployment triggers (no GitHub Actions)
resource "google_pubsub_topic" "deployment_trigger" {
  name    = "${local.env_prefix}-deployment-trigger"
  project = var.gcp_project
}

// Cloud Build trigger subscription handler
resource "google_pubsub_subscription" "deployment_trigger_sub" {
  name            = "${local.env_prefix}-deployment-trigger-sub"
  topic           = google_pubsub_topic.deployment_trigger.name
  project         = var.gcp_project
  ack_deadline_seconds = 10

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic            = google_pubsub_topic.cleanup_dlq.id
    max_delivery_attempts        = 5
  }
}

// API endpoint for direct deployment trigger
resource "google_cloud_run_service" "deployment_api" {
  name     = "${local.env_prefix}-deployment-api"
  location = var.gcp_region
  project  = var.gcp_project

  template {
    spec {
      service_account_name = google_service_account.automation_sa.email
      containers {
        image = "us-docker.pkg.dev/cloud-builders/cloud-builders/gke-deploy:latest"
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
        env {
          name  = "GCP_PROJECT"
          value = var.gcp_project
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

// Allow unauthenticated access to deployment API (service-to-service via internal API only)
resource "google_cloud_run_service_iam_member" "deployment_api_invoker" {
  service  = google_cloud_run_service.deployment_api.name
  location = google_cloud_run_service.deployment_api.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.automation_sa.email}"
}

// ============================================================================
// IMMUTABLE DEPLOYMENT LOGGING & AUDIT
// ============================================================================

resource "google_logging_project_sink" "deployment_audit_log" {
  name        = "${local.env_prefix}-deployment-audit"
  destination = "storage.googleapis.com/${google_storage_bucket.deployment_audit_logs.name}"
  filter      = <<-EOT
    resource.type="cloud_run_revision"
    AND labels.environment="${var.environment}"
  EOT

  unique_writer_identity = true
}

resource "google_storage_bucket" "deployment_audit_logs" {
  name     = "${local.env_prefix}-deployment-audit-logs"
  project  = var.gcp_project
  location = "US"

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  // Immutable object retention - 1 year
  object_retention {
    mode         = "Locked"
    retain_until_ms = 31536000000
  }
}

// Grant the logging sink write permission
resource "google_storage_bucket_iam_member" "audit_sink_writer" {
  bucket = google_storage_bucket.deployment_audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.deployment_audit_log.writer_identity
}

// ============================================================================
// OUTPUTS
// ============================================================================

output "deployment_api_url" {
  value       = google_cloud_run_service.deployment_api.status[0].url
  description = "Direct deployment API endpoint (no GitHub Actions needed)"
}

output "deployment_trigger_topic" {
  value       = google_pubsub_topic.deployment_trigger.name
  description = "Pub/Sub topic for triggering deployments"
}

output "automation_service_account" {
  value       = google_service_account.automation_sa.email
  description = "Service account for all automated operations"
}

output "ephemeral_cleanup_enabled" {
  value       = true
  description = "Automatic ephemeral resource cleanup enabled"
}
