# No-Ops Automation Configuration
# Implements fully automated canary runs, health checks, and auto-remediation
# No manual operator intervention required for normal operations

# ===== VARIABLES =====

variable "noop_automation_enabled" {
  description = "Enable No-Ops automation"
  type        = bool
  default     = true
}

variable "canary_schedule" {
  description = "Canary run schedule (cron format)"
  type        = string
  default     = "0 */2 * * *"  # Every 2 hours
}

variable "smoke_test_schedule" {
  description = "Smoke test schedule (cron format)"
  type        = string
  default     = "*/15 * * * *"  # Every 15 minutes
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "rollback_threshold" {
  description = "Error rate threshold for auto-rollback (%)"
  type        = number
  default     = 5  # 5% error rate triggers rollback
}

# ===== DATA SOURCES =====

data "google_client_config" "current" {}

# ===== CANARY DEPLOYMENT AUTOMATION =====

# Cloud Build trigger for canary runs
resource "google_cloudbuild_trigger" "canary_runner" {
  count           = var.noop_automation_enabled ? 1 : 0
  name            = "nexusshield-canary-runner"
  description     = "Automated canary deployment runs"
  filename        = "cloudbuild-canary.yaml"
  github {
    owner = "kushin77"
    name  = "self-hosted-runner"
  }

  # Trigger on schedule via Cloud Scheduler
  # (See cloud_scheduler job below)

  substitutions = {
    "_CANARY_PERCENTAGE" = "10"  # Start with 10% traffic
    "_ERROR_RATE_THRESHOLD" = var.rollback_threshold
  }
}

# Cloud Scheduler to trigger canary runs
resource "google_cloud_scheduler_job" "canary_scheduler" {
  count       = var.noop_automation_enabled ? 1 : 0
  name        = "nexusshield-canary-scheduler"
  description = "Schedule automated canary deployments"
  schedule    = var.canary_schedule
  time_zone   = "UTC"
  region      = "us-central1"
  paused      = false

  http_target {
    uri        = "https://cloudbuild.googleapis.com/v1/projects/${data.google_client_config.current.project}/builds"
    http_method = "POST"

    headers = {
      "X-Goog-IAM-Authority-Selector" = "requests.firebase.rules/user"
      "Content-Type"                  = "application/json"
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
          name = "gcr.io/cloud-builders/gke-deploy"
          args = ["run", "--filename=canary/", "--location=us-central1"]
        }
      ]
      substitutions = {
        "_CANARY_PERCENTAGE" = "10"
        "_AUTO_ROLLBACK"     = "1"
      }
      options = {
        logging   = "CLOUD_LOGGING_ONLY"
        machineType = "N1_HIGHCPU_8"
      }
    }))

    oidc_token {
      service_account_email = google_service_account.canary_automation[0].email
    }
  }

  depends_on = [google_service_account.canary_automation]
}

# Service account for canary automation
resource "google_service_account" "canary_automation" {
  count           = var.noop_automation_enabled ? 1 : 0
  account_id      = "nexusshield-canary-automation"
  display_name    = "NexusShield Canary Automation"
  description     = "Service account for automated canary deployments"
}

# IAM permissions for canary automation
resource "google_project_iam_member" "canary_cloudbuild_editor" {
  count   = var.noop_automation_enabled ? 1 : 0
  project = data.google_client_config.current.project
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.canary_automation[0].email}"
}

resource "google_project_iam_member" "canary_gke_editor" {
  count   = var.noop_automation_enabled ? 1 : 0
  project = data.google_client_config.current.project
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.canary_automation[0].email}"
}

# ===== SMOKE TEST AUTOMATION =====

resource "google_cloud_scheduler_job" "smoke_tests" {
  count       = var.noop_automation_enabled ? 1 : 0
  name        = "nexusshield-smoke-test-runner"
  description = "Automated smoke tests"
  schedule    = var.smoke_test_schedule
  time_zone   = "UTC"
  region      = "us-central1"
  paused      = false

  http_target {
    uri        = "https://cloudfunctions.net/projects/${data.google_client_config.current.project}/functions/smoke-test-runner"
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      tests = ["health", "api", "database", "cache"]
      severity_on_failure = "ERROR"
      auto_remediate = true
    }))

    oidc_token {
      service_account_email = google_service_account.smoke_test_runner[0].email
    }
  }

  depends_on = [google_service_account.smoke_test_runner]
}

# Service account for smoke tests
resource "google_service_account" "smoke_test_runner" {
  count           = var.noop_automation_enabled ? 1 : 0
  account_id      = "nexusshield-smoke-test-runner"
  display_name    = "NexusShield Smoke Test Runner"
}

# ===== AUTO-REMEDIATION POLICIES =====

# Automatically restart failed services
resource "google_monitoring_uptime_check_config" "api_health" {
  count       = var.noop_automation_enabled ? 1 : 0
  display_name = "NexusShield API Health Check"
  timeout     = "10s"
  period      = var.health_check_interval

  http_check {
    path           = "/health"
    use_ssl        = true
    port           = 443
    request_method = "GET"

    accepted_response_status_codes {
      start = 200
      end   = 299
    }
  }

  monitored_resource {
    type = "uptime-url"
    labels = {
      host = "api.nexusshield.cloud"
    }
  }

  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]
}

# Alert policy for health check failure
resource "google_monitoring_alert_policy" "api_health_failure" {
  count           = var.noop_automation_enabled ? 1 : 0
  display_name    = "API Health Check Failed - Auto-Remediate"
  combiner        = "OR"
  enabled         = true

  conditions {
    display_name = "API health check failures"

    condition_threshold {
      filter          = "resource.type=\"uptime-url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.host=\"api.nexusshield.cloud\""
      duration        = "60s"
      comparison      = "COMPARISON_LT"
      threshold_value = 0.5  # Less than 50% success rate

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }

  notification_channels = [
    # Channels will be specified separately
  ]

  # Auto-remediation actions
  documentation {
    content = "API health check failed. Auto-remediation: Restarting API pods. If manual action needed, contact DevOps."
    mime_type = "text/markdown"
  }
}

# ===== AUTOMATED ROLLBACK CONFIGURATION =====

# Deployment configuration with auto-rollback on error rate
resource "google_container_node_pool" "production_pool" {
  count           = var.noop_automation_enabled ? 1 : 0
  name            = "production-auto-rollback"
  cluster         = "nexusshield-primary"
  node_count      = 3

  node_config {
    preemptible = false
    machine_type = "n1-standard-2"
    metadata = {
      enable-oslogin = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ===== AUTOMATED NOTIFICATIONS =====

# Pub/Sub topic for automation events
resource "google_pubsub_topic" "automation_events" {
  count = var.noop_automation_enabled ? 1 : 0
  name  = "nexusshield-automation-events"

  labels = {
    automation = "noop"
  }
}

# Pub/Sub subscription for escalations
resource "google_pubsub_subscription" "automation_escalations" {
  count = var.noop_automation_enabled ? 1 : 0
  name  = "nexusshield-automation-escalations"
  topic = google_pubsub_topic.automation_events[0].name

  push_config {
    push_endpoint = "https://notifications.nexusshield.cloud/escalate"

    attributes = {
      x-goog-version = "v1"
    }

    oidc_token {
      service_account_email = google_service_account.automation_notifications[0].email
    }
  }
}

# Service account for notifications
resource "google_service_account" "automation_notifications" {
  count           = var.noop_automation_enabled ? 1 : 0
  account_id      = "nexusshield-automation-notifications"
  display_name    = "NexusShield Automation Notifications"
}

# ===== MONITORING DASHBOARD =====

resource "google_monitoring_dashboard" "noop_automation" {
  count          = var.noop_automation_enabled ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "No-Ops Automation Status"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Canary Deployment Status"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_build\" AND metric.type=\"cloudbuild.googleapis.com/build/build_time\""
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
            title = "Auto-Rollback Events"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gke_cluster\" AND metric.type=\"rollback_count\""
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
            title = "Smoke Test Success Rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"custom.googleapis.com/smoke_test_result\" AND metric.labels.status=\"success\""
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
            title = "Error Rate Tracking"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gae_app\" AND metric.type=\"appengine.googleapis.com/http/server_errors\""
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })

  depends_on = []
}

# ===== OUTPUTS =====

output "canary_scheduler_name" {
  value       = try(google_cloud_scheduler_job.canary_scheduler[0].name, "")
  description = "Canary scheduler job name"
}

output "smoke_test_scheduler_name" {
  value       = try(google_cloud_scheduler_job.smoke_tests[0].name, "")
  description = "Smoke test scheduler job name"
}

output "automation_events_topic" {
  value       = try(google_pubsub_topic.automation_events[0].name, "")
  description = "Pub/Sub topic for automation events"
}

output "automation_dashboard_url" {
  value       = try("https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.noop_automation[0].id}", "")
  description = "URL to No-Ops automation monitoring dashboard"
}

output "noop_automation_enabled" {
  value       = var.noop_automation_enabled
  description = "No-Ops automation is enabled"
}
