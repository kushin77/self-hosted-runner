provider "google" {
  project = "nexusshield-prod"
}

resource "google_monitoring_uptime_check_config" "epic5_backend" {
  count        = var.backend_url != "" ? 1 : 0
  display_name = "EPIC-5 Backend health"
  timeout      = "10s"
  period       = "60s"

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = var.backend_url
    }
  }

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }
}

resource "google_monitoring_uptime_check_config" "epic5_frontend" {
  count        = var.frontend_url != "" ? 1 : 0
  display_name = "EPIC-5 Frontend root"
  timeout      = "10s"
  period       = "300s"

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = var.frontend_url
    }
  }

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }
}
