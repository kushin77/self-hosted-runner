terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================================================
# LOGGING MODULE (Already in production from Phase 3)
# ============================================================================
module "logging" {
  source = "../modules/logging"

  project_id   = var.project_id
  environment  = var.environment
  service_name = var.service_name
  region       = var.region
}

# ============================================================================
# MONITORING MODULE (Validated alert policies + dashboards)
# ============================================================================
module "monitoring" {
  source = "../modules/monitoring"

  project_id                    = var.project_id
  environment                  = var.environment
  service_name                 = var.service_name
  region                       = var.region
  alert_cpu_threshold          = var.alert_cpu_threshold
  alert_memory_threshold       = var.alert_memory_threshold
  alert_error_rate_threshold   = var.alert_error_rate_threshold
  alert_latency_p99_threshold  = var.alert_latency_p99_threshold
}

# ============================================================================
# OUTPUTS
# ============================================================================
output "logging_buckets" {
  description = "Log bucket identifiers"
  value = {
    audit       = module.logging.audit_logs_bucket
    application = module.logging.application_logs_bucket
  }
}

output "monitoring_dashboards" {
  description = "Monitoring dashboard IDs"
  value = {
    infrastructure = try(module.monitoring.infrastructure_dashboard_id, "")
    application    = try(module.monitoring.application_dashboard_id, "")
  }
}

output "alert_policies" {
  description = "Alert policy IDs (Phase 4.1 validated)"
  value = {
    cloudsql_cpu      = try(module.monitoring.cloudsql_cpu_alert_id, "")
    cloudsql_memory   = try(module.monitoring.cloudsql_memory_alert_id, "")
    cloudrun_latency  = try(module.monitoring.cloudrun_latency_alert_id, "")
  }
}
