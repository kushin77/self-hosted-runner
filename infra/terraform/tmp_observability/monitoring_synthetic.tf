// Synthetic health-check alerting for custom metric written by synthetic function
// Assumes provider and project are configured in the parent module/root

variable "project" {
  type = string
}

variable "notification_channels" {
  type    = list(string)
  default = []
}

resource "google_monitoring_alert_policy" "synthetic_uptime_alert" {
  display_name = "Synthetic Uptime Check - Failure Alert"
  combiner     = "OR"
  project      = var.project

  dynamic "notification_channels" {
    for_each = var.notification_channels
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
}
