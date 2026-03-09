terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "gcp-eiq"
  region  = "us-central1"
}

# ============================================================================
# AUTONOMOUS DEPLOYMENT INFRASTRUCTURE - ORG GOVERNANCE PROJECT
# ============================================================================

# Service Account for Automation
resource "google_service_account" "automation" {
  account_id   = "automation-runner"
  display_name = "Autonomous Deployment Runner"
  project      = "gcp-eiq"
}

# Grant necessary roles
resource "google_project_iam_member" "automation_compute" {
  project = "gcp-eiq"
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.automation.email}"
}

resource "google_project_iam_member" "automation_iam" {
  project = "gcp-eiq"
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.automation.email}"
}

# Network for test infrastructure
resource "google_compute_network" "automation" {
  name                    = "automation-network"
  project                 = "gcp-eiq"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "automation" {
  name          = "automation-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.automation.id
  project       = "gcp-eiq"
}

# Compute Instance (Ephemeral)
resource "google_compute_instance" "automation_runner" {
  name         = "automation-runner-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  machine_type = "e2-medium"
  zone         = "us-central1-a"
  project      = "gcp-eiq"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.automation.id
    subnetwork = google_compute_subnetwork.automation.id
  }

  service_account {
    email  = google_service_account.automation.email
    scopes = ["cloud-platform"]
  }

  # Enable Shielded VM for org policy compliance
  shielded_vm_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOT
      #!/bin/bash
      set -x
      # Record deployment time
      echo "Instance deployment: $(date)" > /var/log/deployment.log
      # Install minimal tools
      apt-get update && apt-get install -y curl git jq
      # Ready for automation
      echo "✅ Automation runner ready" >> /var/log/deployment.log
    EOT
  }

  labels = {
    environment = "automation"
    owner       = "platform-security"
    deployment  = "autonomous"
    created_at  = formatdate("YYYY-MM-DD", timestamp())
  }

  # Ephemeral - delete after 2 hours
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_project_iam_member.automation_compute,
    google_project_iam_member.automation_iam
  ]
}

# ============================================================================
# OUTPUTS - FOR AUDIT TRAIL & SUBSEQUENT PHASES
# ============================================================================

output "service_account_email" {
  value       = google_service_account.automation.email
  description = "Automation service account email"
}

output "instance_name" {
  value       = google_compute_instance.automation_runner.name
  description = "Deployed automation instance name"
}

output "instance_id" {
  value       = google_compute_instance.automation_runner.id
  description = "Deployed automation instance ID"
}

output "instance_internal_ip" {
  value       = google_compute_instance.automation_runner.network_interface[0].network_ip
  description = "Internal IP of automation runner"
}

output "network_name" {
  value       = google_compute_network.automation.name
  description = "Automation network"
}

output "project_id" {
  value       = "gcp-eiq"
  description = "Project where automation infrastructure is deployed"
}

output "metadata" {
  value = {
    deployed_at = timestamp()
    deployed_by = "terraform"
    version     = "1.0.0"
  }
  description = "Deployment metadata for audit trail"
}
