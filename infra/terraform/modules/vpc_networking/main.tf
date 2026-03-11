/**
 * VPC Networking Module - Main Configuration
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
# VPC NETWORK
# ============================================================================

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = "${var.service_name}-vpc-${var.environment}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"


}

# ============================================================================
# SUBNETS
# ============================================================================

/**
 * Primary subnet for general resources
 * Used for Cloud SQL private service connection
 */
resource "google_compute_subnetwork" "primary" {
  project       = var.project_id
  network       = google_compute_network.main.id
  name          = "${var.service_name}-primary-${var.environment}"
  ip_cidr_range = var.primary_subnet_cidr
  region        = var.region

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }


}

/**
 * Subnet for Cloud Run VPC connector
 * Provides connectivity to private databases/Redis
 */
resource "google_compute_subnetwork" "cloud_run_connector" {
  project       = var.project_id
  network       = google_compute_network.main.id
  name          = "${var.service_name}-cloud-run-${var.environment}"
  ip_cidr_range = var.cloud_run_subnet_cidr
  region        = var.region

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }


}

# ============================================================================
# VPC CONNECTOR FOR CLOUD RUN
# ============================================================================

/**
 * VPC connector enables Cloud Run to connect to private services
 * Required for accessing Cloud SQL and Redis on private IPs
 */
resource "google_vpc_access_connector" "main" {
  project       = var.project_id
  name          = "${var.service_name}-connector-${var.environment}"
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = var.cloud_run_subnet_cidr

  depends_on = [google_compute_subnetwork.cloud_run_connector]
}

# ============================================================================
# CLOUD ROUTER & NAT
# ============================================================================

/**
 * Cloud Router for NAT gateway
 * Enables instances to make outbound requests while staying private
 */
resource "google_compute_router" "main" {
  count   = var.enable_nat ? 1 : 0
  project = var.project_id
  name    = "${var.service_name}-router-${var.environment}"
  region  = var.region
  network = google_compute_network.main.id

  bgp {
    asn = 64514
  }

  labels = var.labels
}

resource "google_compute_router_nat" "main" {
  count                  = var.enable_nat ? 1 : 0
  project                = var.project_id
  name                   = "${var.service_name}-nat-${var.environment}"
  router                 = google_compute_router.main[0].name
  region                 = google_compute_router.main[0].region
  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================================================
# FIREWALL RULES
# ============================================================================

/**
 * Default deny ingress (security best practice)
 */
resource "google_compute_firewall" "deny_ingress" {
  project   = var.project_id
  name      = "${var.service_name}-deny-ingress-${var.environment}"
  network   = google_compute_network.main.name
  direction = "INGRESS"
  priority  = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

}

/**
 * Allow internal communication between subnets
 */
resource "google_compute_firewall" "allow_internal" {
  project   = var.project_id
  name      = "${var.service_name}-allow-internal-${var.environment}"
  network   = google_compute_network.main.name
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [
    var.primary_subnet_cidr,
    var.cloud_run_subnet_cidr,
  ]

  allow {
    protocol = "all"
  }
}

/**
 * Allow health checks from Google Cloud
 */
resource "google_compute_firewall" "allow_health_checks" {
  project   = var.project_id
  name      = "${var.service_name}-allow-health-checks-${var.environment}"
  network   = google_compute_network.main.name
  direction = "INGRESS"
  priority  = 1001

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
}

/**
 * Allow SSH from specific IPs (for debugging only)
 * Empty by default - can be controlled via variable
 */
resource "google_compute_firewall" "allow_ssh" {
  project   = var.project_id
  name      = "${var.service_name}-allow-ssh-${var.environment}"
  network   = google_compute_network.main.name
  direction = "INGRESS"
  priority  = 2000

  source_ranges = [] # Empty - add IPs via terraform.tfvars if needed

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ============================================================================
# PRIVATE SERVICE CONNECTION
# ============================================================================

/**
 * Reserve IP range for private service connections
 * Used by Cloud SQL and other managed services
 */
resource "google_compute_global_address" "private_ip_address" {
  project       = var.project_id
  name          = "${var.service_name}-private-ip-${var.environment}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

/**
 * Private VPC connection for managed services
 */
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "google_project" "current" {
  project_id = var.project_id
}
