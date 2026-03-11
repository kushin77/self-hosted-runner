resource "google_cloud_scheduler_job" "gov_bootstrap_daily" {
  name     = "gov-bootstrap-daily"
  project  = var.project
  location = var.location

  http_target {
    uri        = google_cloud_run_service.gov_bootstrap.status[0].url
    http_method = "POST"

    oidc_token {
      service_account_email = var.scheduler_service_account
    }

    headers = {
      Content-Type = "application/json"
    }
  }

  # Runs daily at 03:00 UTC to ensure the trigger exists and is validated
  schedule  = "0 3 * * *"
  time_zone = "UTC"
}
