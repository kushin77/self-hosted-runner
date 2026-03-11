// Synthetic health-check alerting for custom metric written by synthetic function
// Fetches notification channel IDs from GSM (created via gcloud)

data "google_secret_manager_secret_version" "alert_email_channel" {
  secret      = "synthetic-health-alert-email-channel"
  project     = var.project_id
  version     = "latest"
}

data "google_secret_manager_secret_version" "alert_critical_channel" {
  secret      = "synthetic-health-alert-critical-channel"
  project     = var.project_id
  version     = "latest"
}

locals {
  // Build notification channels list from GSM + variable overrides
  notification_channels = concat(
    [data.google_secret_manager_secret_version.alert_email_channel.secret_data],
    [data.google_secret_manager_secret_version.alert_critical_channel.secret_data],
    var.notification_channels
  )
}

resource "google_monitoring_alert_policy" "synthetic_uptime_alert" {
  display_name = "Synthetic Uptime Check - Failure Alert"
  combiner     = "OR"
  project      = var.project_id

  dynamic "notification_channels" {
    for_each = local.notification_channels
    content {
      notification_channel = notification_channels.value
    }
  }

  conditions {
    display_name = "Synthetic uptime check equals 0"
    condition_threshold {
      filter = "metric.type = \"custom.googleapis.com/synthetic/uptime_check\""
      comparison = "COMPARISON_EQ"
      threshold_value = 0
      duration = "60s"
      aggregations {
        alignment_period = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Fallback: log-based metric created from function structured logs
  conditions {
    display_name = "Synthetic fallback log metric missing"
    condition_threshold {
      filter = "metric.type = \"logging.googleapis.com/user/synthetic_uptime_log_count\""
      comparison = "COMPARISON_LT"
      threshold_value = 1
      duration = "300s"
      aggregations {
        alignment_period = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
}
