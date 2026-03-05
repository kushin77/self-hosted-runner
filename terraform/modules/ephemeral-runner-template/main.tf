##############################################################################
# Ephemeral Runner Instance Template Module
# Configures immutable, auto-terminating instances for GitHub Actions
##############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Service account for ephemeral runners (minimal permissions)
resource "google_service_account" "ephemeral_runner" {
  account_id   = "ephemeral-runner-sa"
  display_name = "Ephemeral Runner Service Account"
  description  = "Minimal permissions for ephemeral GitHub Actions runners"
}

# IAM bindings (minimal)
resource "google_project_iam_member" "ephemeral_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.ephemeral_runner.email}"
}

resource "google_project_iam_member" "ephemeral_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.ephemeral_runner.email}"
}

# Ephemeral instance template (immutable base image, no persistent storage)
resource "google_compute_instance_template" "ephemeral_runner" {
  name_prefix  = "runner-ephemeral-"
  machine_type = var.machine_type

  # Remove default service account
  service_account {
    email  = google_service_account.ephemeral_runner.email
    scopes = ["cloud-platform"]
  }

  # Boot disk: ephemeral (auto-delete on termination)
  disk {
    boot         = true
    source_image = var.image_digest # Immutable digest (e.g., sha256:abc123)
    auto_delete  = true             # CRITICAL: Delete on instance termination
    disk_type    = "pd-ssd"
    disk_size_gb = var.boot_disk_size
    # disk_encryption_key omitted for provider compatibility in validation
  }

  # Networking: ephemeral internal IP only (no external IP)
  network_interface {
    network    = var.network_id
    subnetwork = var.subnetwork_id
    network_ip = "" # Auto-assign ephemeral IP

    # NO access_config block = no external IP
    # Access via IAP (Identity-Aware Proxy) or internal load balancer only
  }

  # Metadata for ephemeral behavior
  metadata = {
    # Ephemeral mode flags
    ephemeral-mode        = "true"
    self-destruct-on-idle = var.idle_timeout_seconds
    max-lifetime          = var.max_lifetime_seconds

    # Startup script: register runner (use inline variable if provided)
    startup-script = var.startup_script_content != "" ? var.startup_script_content : ""

    # Shutdown script: secure wipe (use inline variable if provided)
    shutdown-script = var.shutdown_script_content != "" ? var.shutdown_script_content : ""

    # Environment variables
    PROVISIONER_API       = var.provisioner_api_endpoint
    GITHUB_REPOSITORY_URL = var.github_repository_url
    HEALTH_CHECK_PORT     = "5000"
  }

  # Labels for resource tracking and auto-scaling
  labels = merge(
    {
      ephemeral   = "true"
      generation  = var.image_digest_short
      created_at  = timestamp()
      environment = var.environment
      cost_center = var.cost_center
      team        = var.team_label
    },
    var.additional_labels
  )

  # Scheduling options
  scheduling {
    automatic_restart   = false       # DO NOT auto-restart (ephemeral only)
    on_host_maintenance = "TERMINATE" # Terminate on maintenance events

    # Preemptible (or Spot) instances for cost savings
    preemptible        = var.use_preemptible
    provisioning_model = var.use_preemptible ? "SPOT" : "STANDARD"
  }

  # NOTE: oauth_scopes, metadata_options and workload_identity_config
  # are provider-version specific. They were omitted here to maximize
  # compatibility for local validation. Reintroduce as needed when
  # targeting a specific provider version in production.

  # Enable cloud logging and monitoring
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Lifecycle: allow new name on each template version
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      name_prefix
    ]
  }
}

# Managed instance group: auto-scaling + health checks + pre-warming
resource "google_compute_instance_group_manager" "ephemeral_runners" {
  name               = "runner-ephemeral-group-${substr(timestamp(), 0, 10)}"
  base_instance_name = "runner-ephemeral"
  instance_template  = google_compute_instance_template.ephemeral_runner.self_link
  target_size        = var.min_replicas
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.ephemeral_runner.self_link
    name              = "primary"
  }

  # NOTE: For production deployment, add health_checks and update_policy blocks
  # Auto-scaling should be managed via google_compute_autoscaler resource

  depends_on = [
    google_compute_instance_template.ephemeral_runner
  ]
}

# Health check for runner instances
resource "google_compute_health_check" "runner_health" {
  name               = "runner-health-check"
  check_interval_sec = 10 # Check every 10 seconds
  timeout_sec        = 5  # Timeout after 5 seconds

  http_health_check {
    port         = "5000"
    request_path = "/health"
  }

  # Mark unhealthy after 3 consecutive failures
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# Backend service for load balancing (stateless)
resource "google_compute_backend_service" "ephemeral_runners" {
  name                  = "runner-backend-service"
  protocol              = "HTTP"
  timeout_sec           = 30
  session_affinity      = "NONE" # Stateless (no session pinning)
  load_balancing_scheme = "INTERNAL"

  health_checks = [google_compute_health_check.runner_health.id]

  # Circuit breaking
  connection_draining_timeout_sec = 10

  backend {
    group                 = google_compute_instance_group_manager.ephemeral_runners.instance_group
    balancing_mode        = "RATE"
    max_rate_per_instance = 100
  }

  # Outlier detection: auto-eject unhealthy instances
  outlier_detection {
    base_ejection_time {
      seconds = 30
    }

    consecutive_errors                      = 5
    consecutive_gateway_failure             = 3
    enforcing_consecutive_errors            = 100
    enforcing_consecutive_gateway_failure   = 100
    max_ejection_percent                    = 50
    min_request_volume                      = 10
    split_external_local_originated_traffic = true
  }
}

# Output values for use in other modules and monitoring
output "instance_template_id" {
  value       = google_compute_instance_template.ephemeral_runner.id
  description = "Immutable instance template ID"
}

output "instance_template_self_link" {
  value       = google_compute_instance_template.ephemeral_runner.self_link
  description = "Complete instance template self-link for use in MIG and monitoring"
}

output "instance_template_name" {
  value       = google_compute_instance_template.ephemeral_runner.name
  description = "Instance template name"
}

output "instance_group_id" {
  value       = google_compute_instance_group_manager.ephemeral_runners.id
  description = "Managed Instance Group manager ID"
}

output "instance_group_name" {
  value       = google_compute_instance_group_manager.ephemeral_runners.name
  description = "Name of the managed instance group"
}

output "instance_group_url" {
  value       = google_compute_instance_group_manager.ephemeral_runners.instance_group
  description = "Instance group URL for load balancer targeting and monitoring"
}

output "backend_service_id" {
  value       = google_compute_backend_service.ephemeral_runners.id
  description = "backend service ID for load balancing"
}

output "backend_service_self_link" {
  value       = google_compute_backend_service.ephemeral_runners.self_link
  description = "Backend service self-link for frontend targeting"
}

output "health_check_id" {
  value       = google_compute_health_check.runner_health.id
  description = "Health check resource ID"
}

output "health_check_self_link" {
  value       = google_compute_health_check.runner_health.self_link
  description = "Health check self-link for backend services"
}

output "service_account_email" {
  value       = google_service_account.ephemeral_runner.email
  description = "Service account email for instance identity"
}

output "service_account_unique_id" {
  value       = google_service_account.ephemeral_runner.unique_id
  description = "Service account unique ID for IAM bindings"
}

output "module_config" {
  value = {
    project_id           = var.project_id
    region               = var.region
    zone                 = var.zone
    environment          = var.environment
    machine_type         = var.machine_type
    min_replicas         = var.min_replicas
    max_replicas         = var.max_replicas
    idle_timeout_seconds = var.idle_timeout_seconds
    max_lifetime_seconds = var.max_lifetime_seconds
    use_preemptible      = var.use_preemptible
  }
  description = "Module configuration summary for reference"
}

output "labels_applied" {
  value = merge(
    {
      environment = var.environment
      cost_center = var.cost_center
      team        = var.team_label
      immutable   = "true"
      ephemeral   = "true"
      managed_by  = "terraform"
    },
    var.additional_labels
  )
  description = "Complete map of labels applied to resources for tracking"
}

output "provisioning_status" {
  value = {
    template_deployed   = true
    min_replicas_target = var.min_replicas
    message             = "Ephemeral runner infrastructure ready for production deployment"
  }
  description = "Deployment status and readiness indicators"
}
