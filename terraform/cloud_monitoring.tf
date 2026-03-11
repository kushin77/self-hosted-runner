# Cloud Monitoring: Uptime Checks & Alert Policies for NexusShield Portal
# Ensures 24/7 health monitoring with automated alerting

locals {
  backend_service  = "nexus-shield-portal-backend"
  frontend_service = "nexus-shield-portal-frontend"
  region           = "us-central1"
  alert_email      = var.alert_email != "" ? var.alert_email : "ops@nexusshield.local"
}

# Get Cloud Run backend service URL
data "google_cloud_run_service" "backend" {
  name     = local.backend_service
  location = local.region
  project  = var.gcp_project
}

# Get Cloud Run frontend service URL
data "google_cloud_run_service" "frontend" {
  name     = local.frontend_service
  location = local.region
  project  = var.gcp_project
}

# Backend Uptime Check (Health Endpoint)
resource "google_monitoring_uptime_check_config" "backend_health" {
  project         = var.gcp_project
  display_name    = "NexusShield Backend Health Check (Production)"
  timeout_ms      = 10000
  period_ms       = 60000  # 1 minute interval
  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]

  http_check {
    path           = "/health"
    port           = 443
    request_type   = "HTTPS"
    use_ssl        = true
    accept_redirect = false
  }

  monitored_resource {
    type = "uptime-url"
    labels = {
      host = replace(data.google_cloud_run_service.backend.status[0].url, "https://", "")
    }
  }
}

# Frontend Uptime Check (Main Page)
resource "google_monitoring_uptime_check_config" "frontend_health" {
  project         = var.gcp_project
  display_name    = "NexusShield Frontend Health Check (Production)"
  timeout_ms      = 10000
  period_ms       = 60000  # 1 minute interval
  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]

  http_check {
    path         = "/"
    port         = 443
    request_type = "HTTPS"
    use_ssl      = true
  }

  monitored_resource {
    type = "uptime-url"
    labels = {
      host = replace(data.google_cloud_run_service.frontend.status[0].url, "https://", "")
    }
  }
}

# Backend API Status Check
resource "google_monitoring_uptime_check_config" "backend_api" {
  project         = var.gcp_project
  display_name    = "NexusShield Backend API Status Check (Production)"
  timeout_ms      = 10000
  period_ms       = 60000
  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]

  http_check {
    path           = "/api/v1/status"
    port           = 443
    request_type   = "HTTPS"
    use_ssl        = true
    accept_redirect = false
  }

  monitored_resource {
    type = "uptime-url"
    labels = {
      host = replace(data.google_cloud_run_service.backend.status[0].url, "https://", "")
    }
  }
}

# Email Notification Channel
resource "google_monitoring_notification_channel" "ops_email" {
  project           = var.gcp_project
  display_name      = "NexusShield Ops Team E-mail"
  type              = "email"
  labels = {
    email_address = local.alert_email
  }
  enabled = true
}

# Slack Notification Channel (if webhook provided)
resource "google_monitoring_notification_channel" "ops_slack" {
  count             = var.slack_webhook_url != "" ? 1 : 0
  project           = var.gcp_project
  display_name      = "NexusShield Ops Team Slack"
  type              = "slack"
  labels = {
    channel_name = "#alerts"
  }
  user_labels = {
    slack_channel = "alerts"
  }
  enabled = true
}

# Alert Policy: Backend Health Failures
resource "google_monitoring_alert_policy" "backend_health_failure" {
  project             = var.gcp_project
  display_name        = "Backend Health Check Failed"
  combiner            = "OR"
  alert_strategy {
    auto_close = "1800s"  # Auto close after 30 mins of recovery
  }

  conditions {
    display_name = "Backend health endpoint returning failures"
    condition_threshold {
      filter          = "resource.type=\"uptime-url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.host=\"${replace(data.google_cloud_run_service.backend.status[0].url, "https://", "")}\""
      comparison_operator = "COMPARISON_LT"
      threshold_value = 0.95  # Alert if success rate < 95%
      duration        = "60s"
      aggregations {
        alignment_period  = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.ops_email.id]
}

# Alert Policy: Frontend Health Failures
resource "google_monitoring_alert_policy" "frontend_health_failure" {
  project             = var.gcp_project
  display_name        = "Frontend Health Check Failed"
  combiner            = "OR"
  alert_strategy {
    auto_close = "1800s"
  }

  conditions {
    display_name = "Frontend health endpoint returning failures"
    condition_threshold {
      filter          = "resource.type=\"uptime-url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.host=\"${replace(data.google_cloud_run_service.frontend.status[0].url, "https://", "")}\""
      comparison_operator = "COMPARISON_LT"
      threshold_value = 0.95
      duration        = "60s"
      aggregations {
        alignment_period  = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.ops_email.id]
}

# Alert Policy: Backend API Failures
resource "google_monitoring_alert_policy" "backend_api_failure" {
  project             = var.gcp_project
  display_name        = "Backend API Status Check Failed"
  combiner            = "OR"
  alert_strategy {
    auto_close = "1800s"
  }

  conditions {
    display_name = "Backend API failing health checks"
    condition_threshold {
      filter          = "resource.type=\"uptime-url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.host=\"${replace(data.google_cloud_run_service.backend.status[0].url, "https://", "")}\""
      comparison_operator = "COMPARISON_LT"
      threshold_value = 0.95
      duration        = "60s"
      aggregations {
        alignment_period  = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.ops_email.id]
}

# Outputs
output "backend_uptime_check_id" {
  value       = google_monitoring_uptime_check_config.backend_health.id
  description = "Backend health check resource ID"
}

output "frontend_uptime_check_id" {
  value       = google_monitoring_uptime_check_config.frontend_health.id
  description = "Frontend health check resource ID"
}

output "backend_api_uptime_check_id" {
  value       = google_monitoring_uptime_check_config.backend_api.id
  description = "Backend API status check resource ID"
}

output "notification_channel_email_id" {
  value       = google_monitoring_notification_channel.ops_email.id
  description = "Ops team email notification channel ID"
}
