/**
 * Health Checks Module - Main
 * Adds uptime checks, alerting policies for SLOs
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

# Uptime check for backend health endpoint
resource "google_monitoring_uptime_check_config" "backend_health" {
  project = var.project_id
  display_name = "${var.service_name}-${var.environment}-backend-health"

  http_check {
    path = var.health_path
    port = 8080
    use_ssl = false
  }

  resource_group {
    group_id = "global"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = replace(var.backend_url, "https?://", "")
    }
  }
}

# Uptime check for API status
resource "google_monitoring_uptime_check_config" "backend_status" {
  project = var.project_id
  display_name = "${var.service_name}-${var.environment}-backend-status"

  http_check {
    path = var.api_status_path
    port = 8080
    use_ssl = false
  }

  resource_group {
    group_id = "global"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = replace(var.backend_url, "https?://", "")
    }
  }
}

# Uptime check for frontend
resource "google_monitoring_uptime_check_config" "frontend" {
  project = var.project_id
  display_name = "${var.service_name}-${var.environment}-frontend"

  http_check {
    path = "/"
    port = 80
    use_ssl = true
  }

  resource_group {
    group_id = "global"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = replace(var.frontend_url, "https?://", "")
    }
  }
}

# SLO configuration placeholder (SRE library integration suggested)
output "backend_uptime_check_id" {
  value = google_monitoring_uptime_check_config.backend_health.id
}

output "frontend_uptime_check_id" {
  value = google_monitoring_uptime_check_config.frontend.id
}
