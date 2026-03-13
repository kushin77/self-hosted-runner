# Idempotent Infrastructure Configuration
# Ensures infrastructure stays in sync with Terraform state via:
# - Terraform plan gating in Cloud Build
# - Daily drift detection
# - Automated rollback playbooks
# - Operational automation only (no manual applies)

# ===== VARIABLES =====

variable "idempotent_infrastructure_enabled" {
  description = "Enable idempotent infrastructure management"
  type        = bool
  default     = true
}

variable "terraform_plan_approval_required" {
  description = "Require approval before terraform apply"
  type        = bool
  default     = true
}

variable "drift_detection_schedule" {
  description = "Drift detection schedule (cron format)"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM UTC
}

variable "terraform_backend_region" {
  description = "Region for Terraform state backend"
  type        = string
  default     = "us-central1"
}

variable "rollback_retention_days" {
  description = "How long to retain rollback snapshots"
  type        = number
  default     = 30
}

# ===== DATA SOURCES =====

data "google_client_config" "current" {}

# ===== TERRAFORM STATE MANAGEMENT =====

# GCS bucket for Terraform state with versioning
resource "google_storage_bucket" "terraform_state" {
  count             = var.idempotent_infrastructure_enabled ? 1 : 0
  name              = "nexusshield-terraform-state-${data.google_client_config.current.project}"
  location          = var.terraform_backend_region
  uniform_bucket_level_access = true
  force_destroy     = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      action = "Delete"
    }
  }

  labels = {
    component = "terraform"
    automation = "idempotent"
  }
}

# Bucket IAM restrictions
resource "google_storage_bucket_iam_binding" "terraform_state_access" {
  count  = var.idempotent_infrastructure_enabled ? 1 : 0
  bucket = google_storage_bucket.terraform_state[0].name
  role   = "roles/storage.objectAdmin"

  members = [
    "serviceAccount:${google_service_account.terraform_automation[0].email}",
  ]
}

# ===== TERRAFORM AUTOMATION =====

# Service account for Terraform operations
resource "google_service_account" "terraform_automation" {
  count           = var.idempotent_infrastructure_enabled ? 1 : 0
  account_id      = "nexusshield-terraform-automation"
  display_name    = "NexusShield Terraform Automation"
  description     = "Automation-only (human-readable updates via PR review)"
}

# IAM permissions for Terraform automation
resource "google_project_iam_member" "terraform_editor" {
  count   = var.idempotent_infrastructure_enabled ? 1 : 0
  project = data.google_client_config.current.project
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.terraform_automation[0].email}"
}

# ===== CLOUD BUILD TERRAFORM PLAN GATING =====

# Cloud Build trigger for terraform plan validation
resource "google_cloudbuild_trigger" "terraform_plan_validation" {
  count             = var.idempotent_infrastructure_enabled ? 1 : 0
  name              = "nexusshield-terraform-plan-validation"
  description       = "Validate terraform plan (gating for apply)"
  filename          = "cloudbuild-terraform-plan.yaml"
  disabled          = false
  
  github {
    owner = "kushin77"
    name  = "self-hosted-runner"
    push {
      branch = "^main$"
      paths  = ["terraform/**/*.tf", "terraform/*.tfvars"]
    }
  }

  service_account = "projects/${data.google_client_config.current.project}/serviceAccounts/${google_service_account.terraform_automation[0].email}"

  substitutions = {
    "_REQUIRE_APPROVAL"    = var.terraform_plan_approval_required ? "true" : "false"
    "_BACKEND_BUCKET"      = google_storage_bucket.terraform_state[0].name
    "_TF_VERSION"          = "1.6.0"  # Terraform version
  }
}

# Service account for plan approval (human-readable only)
resource "google_service_account" "terraform_plan_approver" {
  count           = var.idempotent_infrastructure_enabled ? 1 : 0
  account_id      = "nexusshield-terraform-plan-approver"
  display_name    = "Terraform Plan Approver"
  description     = "Can approve terraform plans (requires human review)"
}

# IAM permission for plan approval
resource "google_cloudbuild_worker_pool_iam_binding" "plan_approval" {
  count       = var.idempotent_infrastructure_enabled ? 1 : 0
  resource   = "projects/${data.google_client_config.current.project}/locations/us-central1/workerPools/default"
  role       = "roles/cloudbuild.builds.approver"
  members    = ["serviceAccount:${google_service_account.terraform_plan_approver[0].email}"]
}

# ===== DRIFT DETECTION =====

# Cloud Scheduler job for daily drift detection
resource "google_cloud_scheduler_job" "drift_detection" {
  count       = var.idempotent_infrastructure_enabled ? 1 : 0
  name        = "nexusshield-drift-detection"
  description = "Daily drift detection (terraform plan vs actual resources)"
  schedule    = var.drift_detection_schedule
  time_zone   = "UTC"
  region      = var.terraform_backend_region
  paused      = false

  http_target {
    uri        = "https://cloudbuild.googleapis.com/v1/projects/${data.google_client_config.current.project}/builds"
    http_method = "POST"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      source = {
        repoSource = {
          repoName   = "self-hosted-runner"
          branchName = "main"
        }
      }
      steps = [
        {
          name = "gcr.io/cloud-builders/terraform"
          args = ["init", "-backend-config=bucket=${google_storage_bucket.terraform_state[0].name}"]
          dir  = "terraform"
        },
        {
          name = "gcr.io/cloud-builders/terraform"
          args = ["plan", "-detailed-exitcode"]
          dir  = "terraform"
        },
        {
          name = "gcr.io/cloud-builders/gcloud"
          args = ["logging", "write", "drift-detection", "Drift detection completed", "--severity=INFO"]
        }
      ]
      substitutions = {
        "_DETECT_DRIFT" = "1"
      }
      options = {
        logging   = "CLOUD_LOGGING_ONLY"
        machineType = "N1_STANDARD_1"
      }
    }))

    oidc_token {
      service_account_email = google_service_account.terraform_automation[0].email
    }
  }
}

# Alert policy for drift detection failure
resource "google_monitoring_alert_policy" "drift_detection_failure" {
  count            = var.idempotent_infrastructure_enabled ? 1 : 0
  display_name     = "Infrastructure Drift Detected"
  combiner         = "OR"
  enabled          = true

  conditions {
    display_name = "Terraform drift detected (plan shows changes)"

    condition_threshold {
      filter          = "resource.type=\"cloud_build\" AND protoPayload.methodName=\"cloudbuild.build.create\" AND protoPayload.request.source.repo_source.repo_name=\"self-hosted-runner\" AND protoPayload.request.steps.name=~\".*terraform.*plan.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period = "300s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  notification_channels = []  # Add notification channels

  documentation {
    content = "Infrastructure drift detected. Run: `terraform plan` to review and `terraform apply` to remediate. Requires approval."
    mime_type = "text/markdown"
  }
}

# ===== ROLLBACK AUTOMATION =====

# Cloud Scheduler job for rollback playbook execution
resource "google_cloud_scheduler_job" "rollback_playbook_runner" {
  count       = var.idempotent_infrastructure_enabled ? 1 : 0
  name        = "nexusshield-rollback-playbook-runner"
  description = "Execute rollback playbooks on failed terraform applies"
  schedule    = "*/30 * * * *"  # Every 30 minutes
  time_zone   = "UTC"
  region      = var.terraform_backend_region
  paused      = false

  http_target {
    uri        = "https://cloudfunctions.net/projects/${data.google_client_config.current.project}/functions/rollback-playbook-executor"
    http_method = "POST"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      check_failed_builds = true
      retention_days = var.rollback_retention_days
    }))

    oidc_token {
      service_account_email = google_service_account.terraform_automation[0].email
    }
  }
}

# ===== STATE SNAPSHOTS FOR ROLLBACK =====

# Cloud Storage bucket for Terraform state snapshots
resource "google_storage_bucket" "terraform_snapshots" {
  count             = var.idempotent_infrastructure_enabled ? 1 : 0
  name              = "nexusshield-terraform-snapshots-${data.google_client_config.current.project}"
  location          = var.terraform_backend_region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.rollback_retention_days
    }
    action {
      action = "Delete"
    }
  }

  labels = {
    component = "terraform"
    purpose   = "rollback"
  }
}

# Cloud Function to copy state on each apply
resource "google_cloudfunctions_function" "terraform_state_snapshot" {
  count       = var.idempotent_infrastructure_enabled ? 1 : 0
  name        = "terraform-state-snapshot"
  runtime     = "python39"
  
  source_repository {
    url = "https://github.com/kushin77/self-hosted-runner"
    directory_name = "functions/terraform-state-snapshot"
  }

  event_trigger {
    event_type = "google.storage.object.finalize"
    resource   = google_storage_bucket.terraform_state[0].name
  }

  service_account_email = google_service_account.terraform_automation[0].email
  timeout               = 300
}

# ===== TERRAFORM PLAN GATING CONFIGURATION =====

# Cloud Build configuration stored in repository
# File: cloudbuild-terraform-plan.yaml

# ===== MONITORING DASHBOARD =====

resource "google_monitoring_dashboard" "idempotent_infrastructure" {
  count          = var.idempotent_infrastructure_enabled ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "Idempotent Infrastructure Status"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Terraform Apply Status"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_build\" AND metric.type=\"cloudbuild.googleapis.com/build/build_time\" AND protoPayload.request.substitutions._TERRAFORM_ACTION=\"apply\""
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Drift Detection Events"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_build\" AND metric.type=\"cloudbuild.googleapis.com/build/status\" AND protoPayload.request.substitutions._DETECT_DRIFT=\"1\""
                  }
                }
              }]
            }
          }
        },
        {
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Rollback Events"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"terraform-state-rollback\""
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "State Consistency (Plan Changes Detected)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_build\" AND protoPayload.request.steps.name=~\".*terraform plan.*\""
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
}

# ===== OUTPUTS =====

output "terraform_state_bucket" {
  value       = try(google_storage_bucket.terraform_state[0].name, "")
  description = "Terraform state backend bucket"
}

output "terraform_snapshots_bucket" {
  value       = try(google_storage_bucket.terraform_snapshots[0].name, "")
  description = "Terraform state snapshots for rollback"
}

output "drift_detection_job_name" {
  value       = try(google_cloud_scheduler_job.drift_detection[0].name, "")
  description = "Daily drift detection job"
}

output "terraform_automation_sa_email" {
  value       = try(google_service_account.terraform_automation[0].email, "")
  description = "Service account for Terraform automation"
}

output "idempotent_infrastructure_enabled" {
  value       = var.idempotent_infrastructure_enabled
  description = "Idempotent infrastructure management is enabled"
}

output "plan_approval_required" {
  value       = var.terraform_plan_approval_required
  description = "Terraform apply requires manual approval"
}
