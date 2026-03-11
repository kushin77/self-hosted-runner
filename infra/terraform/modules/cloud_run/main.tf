/**
 * Cloud Run Module - Main Configuration
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Read uptime check token from Secret Manager if provided
data "google_secret_manager_secret_version" "uptime_token" {
  count   = var.uptime_token_secret_name != "" ? 1 : 0
  project = var.project_id
  secret  = var.uptime_token_secret_name
  version = "latest"
}

# ============================================================================
# BACKEND SERVICE
# ============================================================================

resource "google_cloud_run_service" "backend" {
  project  = var.project_id
  name     = "${var.service_name}-backend-${var.environment}"
  location = var.region

  template {
    spec {
      service_account_name = var.service_account_email

      containers {
        image = var.backend_image

        resources {
          limits = {
            memory = var.backend_memory
            cpu    = var.backend_cpu
          }
        }

        # Environment variables
        dynamic "env" {
          for_each = var.environment_variables
          content {
            name  = env.key
            value = env.value
          }
        }

        # Standard environment variables
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }

        env {
          name  = "PORT"
          value = "8080"
        }

        # Uptime check token from Secret Manager (if provided)
        dynamic "env" {
          for_each = var.uptime_token_secret_name != "" ? [1] : []
          content {
            name  = "UPTIME_CHECK_TOKEN"
            value = data.google_secret_manager_secret_version.uptime_token[0].secret_data
          }
        }

        ports {
          container_port = 8080
        }

        # Health check
        startup_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 10
          timeout_seconds       = 5
          period_seconds        = 3
          failure_threshold     = 3
        }

        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          timeout_seconds       = 5
          period_seconds        = 10
          failure_threshold     = 3
        }
      }

      # VPC connector for private database/cache access
      vpc_access_connector {
        name = var.vpc_connector_name
      }

      timeout_seconds = var.timeout_seconds
      max_instances   = var.max_instances
    }

    # Autoscaling
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = var.max_instances
        "autoscaling.knative.dev/minScale" = var.min_instances
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  labels = var.labels
}

# ============================================================================
# BACKEND SERVICE - PUBLIC ACCESS
# ============================================================================

resource "google_cloud_run_service_iam_member" "backend_public" {
  service  = google_cloud_run_service.backend.name
  location = google_cloud_run_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================================
# FRONTEND SERVICE (STATIC SITE)
# ============================================================================

resource "google_cloud_run_service" "frontend" {
  project  = var.project_id
  name     = "${var.service_name}-frontend-${var.environment}"
  location = var.region

  template {
    spec {
      service_account_name = var.service_account_email

      containers {
        image = var.frontend_image

        resources {
          limits = {
            memory = var.frontend_memory
            cpu    = var.frontend_cpu
          }
        }

        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }

        env {
          name  = "PORT"
          value = "3000"
        }

        # Uptime check token from Secret Manager (if provided)
        dynamic "env" {
          for_each = var.uptime_token_secret_name != "" ? [1] : []
          content {
            name  = "UPTIME_CHECK_TOKEN"
            value = data.google_secret_manager_secret_version.uptime_token[0].secret_data
          }
        }

        ports {
          container_port = 3000
        }

        # Health check for static site
        startup_probe {
          http_get {
            path = "/"
            port = 3000
          }
          initial_delay_seconds = 10
          timeout_seconds       = 5
          period_seconds        = 3
          failure_threshold     = 3
        }

        liveness_probe {
          http_get {
            path = "/"
            port = 3000
          }
          initial_delay_seconds = 30
          timeout_seconds       = 5
          period_seconds        = 10
          failure_threshold     = 3
        }
      }

      timeout_seconds = var.timeout_seconds
      max_instances   = var.max_instances
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = var.max_instances
        "autoscaling.knative.dev/minScale" = var.min_instances
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  labels = var.labels
}

# ============================================================================
# FRONTEND SERVICE - PUBLIC ACCESS
# ============================================================================

resource "google_cloud_run_service_iam_member" "frontend_public" {
  service  = google_cloud_run_service.frontend.name
  location = google_cloud_run_service.frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

/* Custom domain mapping removed for provider compatibility. */
# ============================================================================
# DATA SOURCES
# ============================================================================

data "google_project" "current" {
  project_id = var.project_id
}
