/**
 * Cloud Monitoring Module - Main Configuration
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

# ============================================================================
# NOTIFICATION CHANNELS
# ============================================================================

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}-email"
  type         = "email"
  enabled      = true

  labels = {
    email_address = var.notification_email
  }

  user_labels = var.labels
}

resource "google_monitoring_notification_channel" "webhook" {
  count        = var.enable_slack_notification ? 1 : 0
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}-slack"
  type         = "slack"
  enabled      = true

  labels = {
    channel_name = "#alerts"
  }

  user_labels = var.labels
}

# ============================================================================
# INFRASTRUCTURE DASHBOARD
# ============================================================================

resource "google_monitoring_dashboard" "infrastructure" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.service_name} Infrastructure (${var.environment})"
    mosaicLayout = {
      columns = 12
      tiles = [
        # Cloud SQL Metrics
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud SQL CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "CPU (%)"
              }
            }
          }
        },
        # Cloud SQL Memory
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Cloud SQL Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        },
        # Redis CPU
        {
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Redis CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"redis.googleapis.com/Instance\" metric.type=\"redis.googleapis.com/stats/cpu_utilization\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        },
        # Redis Memory
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Redis Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"redis.googleapis.com/Instance\" metric.type=\"redis.googleapis.com/stats/memory_usage_percentage\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        }
      ]
    }
  })
}

# ============================================================================
# APPLICATION DASHBOARD
# ============================================================================

resource "google_monitoring_dashboard" "application" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.service_name} Application (${var.environment})"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Request Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/request_count\""
                    }
                  }
                  plotType = "STACKED_AREA"
                }
              ]
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Error Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/error_rate\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        },
        {
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Response Latency (P99)"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/latency_p99\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        },
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Active Connections"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/active_connections\""
                    }
                  }
                  plotType = "STACKED_AREA"
                }
              ]
            }
          }
        }
      ]
    }
  })
}

# ============================================================================
# ALERT POLICIES
# ============================================================================

# Cloud SQL CPU Alert
resource "google_monitoring_alert_policy" "cloudsql_cpu" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}: Cloud SQL High CPU"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL CPU Utilization"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold / 100
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}

# Cloud SQL Memory Alert
resource "google_monitoring_alert_policy" "cloudsql_memory" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}: Cloud SQL High Memory"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL Memory Utilization"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold / 100
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}

# Redis CPU Alert
resource "google_monitoring_alert_policy" "redis_cpu" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}: Redis High CPU"
  combiner     = "OR"

  conditions {
    display_name = "Redis CPU Utilization"
    condition_threshold {
      filter          = "resource.type=\"redis.googleapis.com/Instance\" AND metric.type=\"redis.googleapis.com/stats/cpu_utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold / 100
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}

# Redis Memory Alert
resource "google_monitoring_alert_policy" "redis_memory" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}: Redis High Memory"
  combiner     = "OR"

  conditions {
    display_name = "Redis Memory Utilization"
    condition_threshold {
      filter          = "resource.type=\"redis.googleapis.com/Instance\" AND metric.type=\"redis.googleapis.com/stats/memory_usage_percentage\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold / 100
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}

# Cloud Run Error Rate Alert
resource "google_monitoring_alert_policy" "cloudrun_errors" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}: Cloud Run High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run Error Rate"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.response_code_class=\"5xx\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_error_rate_threshold / 100
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}

# Cloud Run Latency Alert
resource "google_monitoring_alert_policy" "cloudrun_latency" {
  project      = var.project_id
  display_name = "${var.service_name}-${var.environment}: Cloud Run High Latency"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run P99 Latency"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_latency_p99_threshold * 1000  # Convert to milliseconds
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}
