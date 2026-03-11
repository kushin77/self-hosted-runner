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
  count        = var.enable_checks && var.backend_host != "" ? 1 : 0
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}-backend-health"

  timeout = "10s"

  http_check {
    path    = var.health_path
    port    = 443
    use_ssl = true
    headers = var.auth_headers
  }
  monitored_resource {
    type = "uptime-url"
    labels = {
      host = var.backend_host
    }
  }
}

# Uptime check for API status
resource "google_monitoring_uptime_check_config" "backend_status" {
  count        = var.enable_checks && var.backend_host != "" ? 1 : 0
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}-backend-status"

  timeout = "10s"

  http_check {
    path    = var.api_status_path
    port    = 443
    use_ssl = true
    headers = var.auth_headers
  }
  monitored_resource {
    type = "uptime-url"
    labels = {
      host = var.backend_host
    }
  }
}

# Uptime check for frontend
resource "google_monitoring_uptime_check_config" "frontend" {
  count        = var.enable_checks && var.frontend_host != "" ? 1 : 0
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}-frontend"

  timeout = "10s"

  http_check {
    path    = "/"
    port    = 443
    use_ssl = true
    headers = var.auth_headers
  }
  monitored_resource {
    type = "uptime-url"
    labels = {
      host = var.frontend_host
    }
  }
}

# SLO configuration placeholder (SRE library integration suggested)
output "backend_uptime_check_id" {
  value = length(google_monitoring_uptime_check_config.backend_health) > 0 ? google_monitoring_uptime_check_config.backend_health[0].id : ""
}

output "frontend_uptime_check_id" {
  value = length(google_monitoring_uptime_check_config.frontend) > 0 ? google_monitoring_uptime_check_config.frontend[0].id : ""
}
