resource "google_monitoring_notification_channel" "email" {
  display_name = "Email - EPIC-5 Alerts"
  type         = "email"

  labels = {
    email_address = "support@elevatediq.ai"
  }
}

resource "google_monitoring_alert_policy" "epic5_uptime" {
  display_name = "EPIC-5 Uptime Alert"
  combiner     = "OR"

  notification_channels = [
    google_monitoring_notification_channel.email.name,
  ]

  conditions {
    display_name = "Backend uptime check failed"
    condition_threshold {
      filter = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" resource.label.host=\"${var.backend_url}\""
      duration = "60s"
      comparison = "COMPARISON_LT"
      threshold_value = 1

      # No aggregation required for boolean uptime_check/check_passed metric
    }
  }

  conditions {
    display_name = "Frontend uptime check failed"
    condition_threshold {
      filter = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" resource.label.host=\"${var.frontend_url}\""
      duration = "300s"
      comparison = "COMPARISON_LT"
      threshold_value = 1

      # No aggregation required for boolean uptime_check/check_passed metric
    }
  }
}
