resource "google_cloudbuild_trigger" "gov_scan" {
  name = "gov-scan-trigger"

  github {
    owner = "kushin77"
    name  = "self-hosted-runner"
    push {
      branch = "^main$"
    }
  }

  filename = "governance/cloudbuild-gov-scan.yaml"
}

# Cloud Scheduler job to trigger the build trigger via Cloud Build REST API
resource "google_cloud_scheduler_job" "gov_scan_daily" {
  name     = "gov-scan-daily"
  project  = var.project
  region   = var.location

  http_target {
    uri        = "https://cloudbuild.googleapis.com/v1/projects/${var.project}/triggers/${google_cloudbuild_trigger.gov_scan.id}:run"
    http_method = "POST"

    oidc_token {
      service_account_email = var.scheduler_service_account
    }

    headers = {
      Content-Type = "application/json"
    }
  }

  schedule = "0 3 * * *"
  time_zone = "UTC"
}
