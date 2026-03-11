resource "google_cloud_run_service" "gov_bootstrap" {
  name     = "gov-bootstrap"
  location = var.location

  template {
    spec {
      containers {
        image = "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
        env {
          name  = "PROJECT"
          value = var.project
        }
        env {
          name  = "TRIGGER_NAME"
          value = "gov-scan-trigger"
        }
        args = [
          "bash",
          "-c",
          "set -euo pipefail; gcloud --quiet config set project ${PROJECT} ; gcloud --quiet beta builds triggers create github --name=\"${TRIGGER_NAME}\" --repo-name=\"self-hosted-runner\" --repo-owner=\"kushin77\" --branch-pattern=\"^main$\" --build-config=\"governance/cloudbuild-gov-scan.yaml\" || true ; gcloud --quiet beta builds triggers run ${TRIGGER_NAME} --branch=main || true ; echo BOOTSTRAP_DONE"
        ]
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Allow scheduler (or admins) to invoke the Cloud Run service. The caller must supply `scheduler_service_account` variable.
resource "google_cloud_run_service_iam_member" "invoker" {
  location = google_cloud_run_service.gov_bootstrap.location
  project  = var.project
  service  = google_cloud_run_service.gov_bootstrap.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.scheduler_service_account}"
}
