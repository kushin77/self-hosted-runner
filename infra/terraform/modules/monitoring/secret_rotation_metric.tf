resource "google_logging_metric" "secret_rotation_metric" {
  name        = "secret_rotation_events_${var.secret_id}"
  project     = var.project_id
  description = "Counts Secret Manager secret version creations for ${var.secret_id}"
  filter      = "resource.type=\"secret\" AND protoPayload.methodName=\"google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion\" AND resource.labels.secret_id=\"${var.secret_id}\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "secret_rotation_alert" {
  count        = length(var.notification_channels) > 0 ? 1 : 0
  display_name = "Secret rotation missing for ${var.secret_id}"
  combiner     = "AND"

  notification_channels = var.notification_channels

  conditions {
    display_name = "No secret rotation in 24h"
    condition_threshold {
      filter = "metric.type=\"logging.googleapis.com/user/secret_rotation_events_${var.secret_id}\""
      aggregations {
        alignment_period    = "86400s"
        per_series_aligner  = "ALIGN_SUM"
      }
      comparison     = "COMPARISON_LT"
      threshold_value = 1
      duration       = "0s"
    }
  }
  project = var.project_id
}
