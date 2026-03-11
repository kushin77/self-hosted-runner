/**
 * Cloud Logging Module - Main Configuration
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
# CLOUD LOGGING BUCKETS
# ============================================================================

resource "google_logging_project_bucket_config" "audit_logs" {
  project        = var.project_id
  location       = var.logs_bucket_location
  bucket_id      = "${var.service_name}-audit-logs-${var.environment}"
  retention_days = var.audit_logs_retention_days
  description    = "Audit logs bucket for ${var.environment}"

  locked = false
}

resource "google_logging_project_bucket_config" "application_logs" {
  project        = var.project_id
  location       = var.logs_bucket_location
  bucket_id      = "${var.service_name}-app-logs-${var.environment}"
  retention_days = var.application_logs_retention_days
  description    = "Application logs bucket for ${var.environment}"

  locked = false
}

# ============================================================================
# LOG SINKS - CLOUD RUN LOGS
# ============================================================================

resource "google_logging_project_sink" "cloudrun_logs" {
  name        = "${var.service_name}-cloud-run-${var.environment}"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.logs_bucket_location}/buckets/${google_logging_project_bucket_config.application_logs.bucket_id}"
  filter      = "resource.type=\"cloud_run_revision\""

  unique_writer_identity = true
}

# ============================================================================
# LOG SINKS - CLOUD SQL LOGS
# ============================================================================

resource "google_logging_project_sink" "cloudsql_logs" {
  name        = "${var.service_name}-cloud-sql-${var.environment}"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.logs_bucket_location}/buckets/${google_logging_project_bucket_config.application_logs.bucket_id}"
  filter      = "resource.type=\"cloudsql_database\""

  unique_writer_identity = true
}

# ============================================================================
# LOG SINKS - AUDIT LOGS
# ============================================================================

resource "google_logging_project_sink" "audit_logs_sink" {
  name        = "${var.service_name}-audit-logs-${var.environment}"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.logs_bucket_location}/buckets/${google_logging_project_bucket_config.audit_logs.bucket_id}"
  filter      = "protoPayload.methodName!=\"\" OR resource.type=\"gce_firewall_rule\""

  unique_writer_identity = true
}

# ============================================================================
# LOG SINKS - VPC FLOW LOGS
# ============================================================================

resource "google_logging_project_sink" "vpc_flow_logs" {
  name        = "${var.service_name}-vpc-flow-logs-${var.environment}"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.logs_bucket_location}/buckets/${google_logging_project_bucket_config.application_logs.bucket_id}"
  filter      = "resource.type=\"gce_subnetwork\""

  unique_writer_identity = true
}

# ============================================================================
# LOG SINKS - REDIS LOGS
# ============================================================================

resource "google_logging_project_sink" "redis_logs" {
  name        = "${var.service_name}-redis-${var.environment}"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.logs_bucket_location}/buckets/${google_logging_project_bucket_config.application_logs.bucket_id}"
  filter      = "resource.type=\"redis.googleapis.com/Instance\""

  unique_writer_identity = true
}

# ============================================================================
# LOG-BASED METRICS
# ============================================================================

resource "google_logging_metric" "error_count" {
  name   = "${var.service_name}-error-count-${var.environment}"
  filter = "severity=\"ERROR\" OR severity=\"CRITICAL\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_logging_metric" "error_rate" {
  name   = "${var.service_name}-error-rate-${var.environment}"
  filter = "httpRequest.status>=400"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_logging_metric" "latency_p99" {
  name   = "${var.service_name}-latency-p99-${var.environment}"
  filter = "httpRequest.latency!=\"\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
  }

  value_extractor = "EXTRACT(httpRequest.latency)"

  # Bucket options required for DISTRIBUTION metrics (prevents provider schema errors)
  bucket_options {
    exponential_buckets {
      num_finite_buckets = 8
      growth_factor       = 2.0
      scale               = 0.001
    }
  }
}
