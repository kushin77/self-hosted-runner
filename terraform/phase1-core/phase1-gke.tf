# ============================================================================
# PHASE 1: GKE CLUSTER FOR WEBHOOK INGESTION & NORMALIZATION
# ============================================================================
#
# This file creates the GKE cluster for Phase 1 deployment
# - Immutable infrastructure as code
# - Ephemeral, idempotent design
# - GSM/KMS secrets management  
# - No manual operations
#
# ============================================================================

# ============================================================================
# GKE CLUSTER (nexus-prod-gke)
# ============================================================================

resource "google_container_cluster" "nexus_prod" {
  name              = var.gke_cluster_name
  location          = var.gke_zone
  project           = var.project_id
  
  # Set initial_node_count = 1 for cluster creation, managed node pool will override
  initial_node_count = 1
  
  # Network configuration
  network    = "default"
  subnetwork = "default"

  # Cluster configuration
  cluster_autoscaling {
    enabled = true
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Security
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Monitoring and logging
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # IP aliasing for pod networking
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Additional cluster features
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"  # 3 AM UTC
    }
  }

  depends_on = [
    google_project_service.container_api
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# NODE POOL (default)
# ============================================================================

resource "google_container_node_pool" "nexus_prod_nodes" {
  name       = "nexus-prod-node-pool"
  location   = var.gke_zone
  cluster    = google_container_cluster.nexus_prod.name
  project    = var.project_id
  
  initial_node_count = 3

  autoscaling {
    min_node_count = 2
    max_node_count = 10
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = "n1-standard-2"

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # OAuth scopes for GCP services
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Service account
    service_account = google_service_account.gke_nodes_sa.email

    # Labels
    labels = {
      "pool"    = "nexus-prod"
      "managed" = "terraform"
    }

    # Disk configuration
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Taints (to control pod scheduling)
    taint {
      key    = "workload"
      value  = "nexus"
      effect = "NO_SCHEDULE"
    }
  }

  depends_on = [
    google_container_cluster.nexus_prod,
    google_service_account.gke_nodes_sa
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# SERVICE ACCOUNTS
# ============================================================================

# GKE node pool service account
resource "google_service_account" "gke_nodes_sa" {
  account_id   = "nexus-gke-nodes"
  display_name = "GKE node pool service account for Nexus Phase 1"
  project      = var.project_id
}

# GKE pod service account (for workload identity)
resource "google_service_account" "nexus_discovery_sa" {
  account_id   = "nexus-discovery-pod"
  display_name = "Nexus Discovery pod service account"
  project      = var.project_id
}

# ============================================================================
# WORKLOAD IDENTITY BINDING
# ============================================================================

# Allow pods to impersonate the nexus-discovery service account via Workload Identity
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.nexus_discovery_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[nexus-discovery/nexus-discovery]"
}

# ============================================================================
# IAM ROLES
# ============================================================================

# GKE node permissions (basic)
resource "google_project_iam_member" "gke_nodes_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

# Nexus discovery pod permissions
resource "google_project_iam_member" "nexus_discovery_gsm" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.nexus_discovery_sa.email}"
}

# ============================================================================
# GCP SERVICES (Enable if not already enabled)
# ============================================================================

resource "google_project_service" "container_api" {
  project = var.project_id
  service = "container.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "gke_cluster_name" {
  value       = google_container_cluster.nexus_prod.name
  description = "GKE cluster name"
}

output "gke_region" {
  value       = var.gke_zone
  description = "GKE cluster zone"
}

output "gke_ca_certificate" {
  value       = base64encode(google_container_cluster.nexus_prod.master_auth[0].cluster_ca_certificate)
  description = "GKE cluster CA certificate"
  sensitive   = true
}

output "gke_host" {
  value       = "https://${google_container_cluster.nexus_prod.endpoint}"
  description = "GKE cluster endpoint"
}
