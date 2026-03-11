variable "project" { type = string }

resource "google_logging_metric" "secret_rotation_metric" {
  name   = "secret_rotation_events"
  project = var.project
  description = "Counts Secret Manager secret version creations for uptime-check-token"
  filter = "resource.type=\"secret\" AND protoPayload.methodName=\"google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion\" AND resource.labels.secret_id=\"uptime-check-token\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "secret_rotation_alert" {
  display_name = "Secret rotation missing for uptime-check-token"
  combiner = "AND"

  notification_channels = [] # configure as needed

  conditions {
    display_name = "No secret rotation in 24h"
    condition_threshold {
      filter = "metric.type=\"logging.googleapis.com/user/secret_rotation_events\""
      aggregations {
        alignment_period = "86400s"
        per_series_aligner = "ALIGN_SUM"
      }
      comparison = "COMPARISON_LT"
      threshold_value = 1
      duration = "0s"
    }
  }
  project = var.project
}
