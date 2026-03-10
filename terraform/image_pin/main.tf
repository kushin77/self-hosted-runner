terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Cloud Run service for image-pin
resource "google_cloud_run_service" "image_pin" {
  name     = "image-pin-service"
  location = var.region

  template {
    spec {
      containers {
        image = var.image
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "LOCATION"
          value = var.region
        }
      }
    }
  }

  traffics {
    percent         = 100
    latest_revision = true
  }
}

# Cloud Scheduler job to call the Cloud Run service (HTTP)
resource "google_cloud_scheduler_job" "image_pin_scheduler" {
  name = "image-pin-scheduler"
  description = "Trigger image-pin service on schedule"
  schedule = var.schedule
  time_zone = "UTC"

  http_target {
    uri = "https://${google_cloud_run_service.image_pin.status[0].url}/pin"
    http_method = "POST"
    oidc_token {
      service_account_email = var.scheduler_sa
    }
    body = base64encode(jsonencode({
      repository = var.repository,
      image_name = var.image_name,
      tag = var.tag
    }))
  }
}
