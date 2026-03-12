# Cloud SQL Proxy sidecar for backend service
# Enables cloud-sql-proxy to run alongside backend container
# Reference: https://cloud.google.com/sql/docs/mysql/sql-proxy

variable "enable_cloud_sql_proxy" {
  description = "Enable Cloud SQL Auth Proxy sidecar in backend Cloud Run service"
  type        = bool
  default     = false
}

variable "cloud_sql_instance_connection_name" {
  description = "Cloud SQL instance connection name (format: project:region:instance)"
  type        = string
  default     = ""
}

variable "cloud_sql_proxy_port" {
  description = "Port cloud-sql-proxy listens on inside container"
  type        = number
  default     = 5432
}

variable "backend_sa_email" {
  description = "Backend service account email (needs cloudsql.client role)"
  type        = string
  default     = ""
}

# Grant backend service account permission to connect to Cloud SQL
resource "google_project_iam_member" "backend_cloudsql_client" {
  count   = var.enable_cloud_sql_proxy && var.backend_sa_email != "" ? 1 : 0
  project = var.gcp_project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.backend_sa_email}"
}

# Cloud SQL proxy sidcar container definition
# This is merged into the Cloud Run service spec
locals {
  cloud_sql_proxy_container = var.enable_cloud_sql_proxy && var.cloud_sql_instance_connection_name != "" ? [{
    image = "gcr.io/cloudsql-docker/cloud-sql-proxy:2.7.0"
    args = [
      var.cloud_sql_instance_connection_name,
      "--port=${var.cloud_sql_proxy_port}",
      "--max-connections=100",
      "--use-http-health-check",
      "--health-check-port=8090"
    ]
    ports {
      container_port = var.cloud_sql_proxy_port
      name           = "cloudsql"
    }
    resources {
      limits = {
        cpu    = "500m"
        memory = "256Mi"
      }
    }
    liveness_probe {
      http_get {
        path = "/"
        port = 8090
      }
      initial_delay_seconds = 10
      period_seconds        = 10
    }
    readiness_probe {
      http_get {
        path = "/"
        port = 8090
      }
      initial_delay_seconds = 5
      period_seconds        = 5
    }
  }] : []
}

output "cloud_sql_proxy_enabled" {
  value       = var.enable_cloud_sql_proxy
  description = "Whether Cloud SQL proxy is enabled"
}

output "cloud_sql_proxy_port" {
  value       = var.cloud_sql_proxy_port
  description = "Port cloud-sql-proxy listens on (use localhost:5432 in app)"
}

output "cloud_sql_proxy_iam_binding" {
  value       = var.enable_cloud_sql_proxy && var.backend_sa_email != "" ? "roles/cloudsql.client granted to ${var.backend_sa_email}" : "Not enabled"
  description = "Cloud SQL client role binding status"
}
