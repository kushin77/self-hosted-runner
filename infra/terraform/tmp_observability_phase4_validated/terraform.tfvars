# Phase 4.1 Validated Observability (Logging + Cloud SQL Alerts)
project_id     = "nexusshield-prod"
environment    = "dev"
service_name   = "nexus-shield"
region         = "us-central1"

# Alert thresholds
alert_cpu_threshold          = 80
alert_memory_threshold       = 85
alert_error_rate_threshold   = 5
alert_latency_p99_threshold  = 2 # seconds
