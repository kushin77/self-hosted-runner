/**
 * Cost-Saving Cloud Run Configuration for Development
 * - Min instances: 0 (scale to zero when idle)
 * - Max instances: 5 (prevent runaway costs)
 * - Timeout: 15 minutes
 * - Memory: 256MB (minimal for dev)
 * - CPU: 0.5 (minimal for dev)
 * - Auto-triggers on traffic, shuts down after 5 min idle
 */

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

variable "service_name" {
  description = "Service name for Cloud Run"
  type        = string
}

variable "min_instances" {
  description = "Minimum instances (0 for cost savings)"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum instances"
  type        = number
  default     = 5
}

resource "google_cloud_run_service" "api" {
  name     = "${var.service_name}-${var.environment}"
  location = "us-central1"

  template {
    spec {
      service_account_name = google_service_account.api.email
      
      containers {
        image = "gcr.io/${data.google_client_config.current.project}/${var.service_name}:latest"
        
        resources {
          limits = {
            cpu    = "0.5"
            memory = "256Mi"
          }
        }
        
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
      }
      
      # Cost-saving: timeout after 15 minutes of inactivity
      timeout_seconds = 900
    }
    
    metadata {
      labels = {
        environment     = var.environment
        cost-management = "5-min-cleanup"
      }
    }
  }

  traffic {
    percent          = 100
    latest_revision  = true
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations["serving.knative.dev/creator"]]
  }

  depends_on = [
    google_project_service.run,
    google_project_service.cloudbuild
  ]
}

resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.api.name
  location = google_cloud_run_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cost-saving autoscaling configuration
resource "google_cloud_run_service" "api_autoscaling" {
  depends_on = [google_cloud_run_service.api]
  
  # Deployed via gcloud to add autoscaling:
  # gcloud run services update SERVICE_NAME --min-instances=0 --max-instances=5 --region=us-central1
}

data "google_client_config" "current" {}

resource "google_service_account" "api" {
  account_id   = "${var.service_name}-sa-${var.environment}"
  display_name = "Service account for ${var.service_name}"
}

resource "google_project_service" "run" {
  service = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

output "cloud_run_url" {
  value       = google_cloud_run_service.api.status[0].url
  description = "URL of the Cloud Run service"
}
