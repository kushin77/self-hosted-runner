# On-Premises Redundancy and VPN Failover Configuration
# This configuration implements:
# - Primary Cloud Interconnect for on-prem to GCP connectivity
# - Backup VPN tunnel for automatic failover
# - Centralized SSH key management via HashiCorp Vault
# - Automatic key rotation (30-day cycle)
# - Multi-path routing for redundancy

# ===== VARIABLES =====

variable "onprem_redundancy_enabled" {
  description = "Enable on-premises redundancy configuration"
  type        = bool
  default     = true
}

variable "onprem_primary_asn" {
  description = "BGP ASN for on-premises (primary)"
  type        = number
  default     = 65000
}

variable "onprem_secondary_asn" {
  description = "BGP ASN for on-premises (secondary/backup)"
  type        = number
  default     = 65001
}

variable "gcp_onprem_asn" {
  description = "BGP ASN for GCP side"
  type        = number
  default     = 64512
}

variable "vault_address" {
  description = "HashiCorp Vault address"
  type        = string
  default     = "https://vault.nexusshield.cloud:8200"
}

variable "vault_namespace" {
  description = "Vault namespace for secret management"
  type        = string
  default     = "nexusshield"
}

variable "ssh_key_rotation_days" {
  description = "SSH key rotation interval in days"
  type        = number
  default     = 30
}

variable "primary_interconnect_region" {
  description = "Primary Cloud Interconnect region"
  type        = string
  default     = "us-central1"
}

variable "backup_vpn_region" {
  description = "Backup VPN region (different from primary)"
  type        = string
  default     = "us-east1"
}

# ===== DATA SOURCES =====

data "google_client_config" "current" {}

# ===== PRIMARY CLOUD INTERCONNECT =====
# For dedicated high-bandwidth connection to on-premises

resource "google_compute_interconnect_attachment" "primary_onprem" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-primary-interconnect-${data.google_client_config.current.project}"
  router          = google_compute_router.onprem_primary[0].id
  region          = var.primary_interconnect_region
  type            = "PARTNER"  # Google Partner Interconnect (lower cost than Dedicated)
  bandwidth       = "50Mbps"   # Scalable up to 10Gbps

  candidate_ipv4_ranges = ["169.254.10.0/24"]
  ips_reserved          = ["169.254.10.1", "169.254.10.2"]

  # Edge availability domain for redundancy
  edge_availability_domain = "AVAILABILITY_DOMAIN_ANY"

  encryption {
    type = "NONE"  # MACsec encryption should be enabled in production
  }

  depends_on = [
    google_compute_router.onprem_primary,
    google_compute_network.onprem_vpc
  ]
}

# ===== PRIMARY VPC ROUTER FOR INTERCONNECT =====

resource "google_compute_router" "onprem_primary" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name    = "nexusshield-onprem-primary-router"
  region  = var.primary_interconnect_region
  network = google_compute_network.onprem_vpc.id
  asn     = var.gcp_onprem_asn

  bgp {
    asn                = var.gcp_onprem_asn
    advertise_mode     = "CUSTOM"
    advertised_groups  = ["ALL_SUBNETS"]
    advertised_routes  = ["10.40.0.0/16"]  # On-prem CIDR
  }
}

# BGP peer for primary interconnect
resource "google_compute_router_peer" "primary_onprem_bgp" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-primary-bgp-peer"
  router          = google_compute_router.onprem_primary[0].name
  region          = google_compute_router.onprem_primary[0].region
  peer_asn        = var.onprem_primary_asn
  peer_ip_address = "169.254.10.2"  # Remote BGP peer IP
}

# ===== BACKUP VPN TUNNEL =====
# Automatic failover tunnel if Interconnect fails

resource "google_compute_vpn_gateway" "onprem_backup" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name    = "nexusshield-backup-vpn-${data.google_client_config.current.project}"
  network = google_compute_network.onprem_vpc.id
  region  = var.backup_vpn_region
  type    = "HA_VPN"  # High availability VPN

  depends_on = [google_compute_network.onprem_vpc]
}

# Backup VPN tunnel (Primary to Backup)
resource "google_compute_vpn_tunnel" "backup_tunnel_1" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name              = "nexusshield-backup-vpn-tunnel-1"
  vpn_gateway       = google_compute_vpn_gateway.onprem_backup[0].id
  peer_external_gateway = google_compute_external_vpn_gateway.onprem_backup[0].id
  shared_secret     = random_password.vpn_shared_secret[0].result
  router            = google_compute_router.onprem_backup[0].name
  vpn_gateway_interface = 0
  peer_external_gateway_interface = 0
  ike_version      = 2

  depends_on = [
    google_compute_router_interface.backup_tunnel_1
  ]
}

# Backup VPN tunnel (Secondary to Backup)
resource "google_compute_vpn_tunnel" "backup_tunnel_2" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name              = "nexusshield-backup-vpn-tunnel-2"
  vpn_gateway       = google_compute_vpn_gateway.onprem_backup[0].id
  peer_external_gateway = google_compute_external_vpn_gateway.onprem_backup[0].id
  shared_secret     = random_password.vpn_shared_secret[0].result
  router            = google_compute_router.onprem_backup[0].name
  vpn_gateway_interface = 1
  peer_external_gateway_interface = 1
  ike_version      = 2

  depends_on = [
    google_compute_router_interface.backup_tunnel_2
  ]
}

# Backup VPC Router
resource "google_compute_router" "onprem_backup" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name    = "nexusshield-onprem-backup-router"
  region  = var.backup_vpn_region
  network = google_compute_network.onprem_vpc.id
  asn     = var.gcp_onprem_asn

  bgp {
    asn                = var.gcp_onprem_asn
    advertise_mode     = "CUSTOM"
    advertised_groups  = ["ALL_SUBNETS"]
    advertised_routes  = ["10.40.0.0/16"]  # On-prem CIDR
  }
}

# Router interfaces for VPN tunnels
resource "google_compute_router_interface" "backup_tunnel_1" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-backup-tunnel-1-interface"
  router          = google_compute_router.onprem_backup[0].name
  region          = google_compute_router.onprem_backup[0].region
  ip_range        = "169.254.20.1/30"
  vpn_tunnel      = google_compute_vpn_tunnel.backup_tunnel_1[0].name
}

resource "google_compute_router_interface" "backup_tunnel_2" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-backup-tunnel-2-interface"
  router          = google_compute_router.onprem_backup[0].name
  region          = google_compute_router.onprem_backup[0].region
  ip_range        = "169.254.21.1/30"
  vpn_tunnel      = google_compute_vpn_tunnel.backup_tunnel_2[0].name
}

# BGP peer for backup VPN (Primary on-prem)
resource "google_compute_router_peer" "backup_tunnel_1_bgp" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-backup-vpn-bgp-1"
  router          = google_compute_router.onprem_backup[0].name
  region          = google_compute_router.onprem_backup[0].region
  peer_asn        = var.onprem_primary_asn
  peer_ip_address = "169.254.20.2"
  interface       = google_compute_router_interface.backup_tunnel_1[0].name
}

# BGP peer for backup VPN (Secondary on-prem)
resource "google_compute_router_peer" "backup_tunnel_2_bgp" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-backup-vpn-bgp-2"
  router          = google_compute_router.onprem_backup[0].name
  region          = google_compute_router.onprem_backup[0].region
  peer_asn        = var.onprem_secondary_asn
  peer_ip_address = "169.254.21.2"
  interface       = google_compute_router_interface.backup_tunnel_2[0].name
}

# External VPN Gateway (On-premises)
resource "google_compute_external_vpn_gateway" "onprem_backup" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name            = "nexusshield-onprem-external-vpn"
  redundancy_type = "TWO_IPS_REDUNDANCY"

  interface {
    id         = 0
    ip_address = "203.0.113.12"  # Update with actual on-prem primary gateway IP
  }

  interface {
    id         = 1
    ip_address = "203.0.113.13"  # Update with actual on-prem secondary gateway IP
  }
}

# ===== SHARED VPN SECRET =====

resource "random_password" "vpn_shared_secret" {
  count            = var.onprem_redundancy_enabled ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ===== ON-PREMISES VPC NETWORK =====

resource "google_compute_network" "onprem_vpc" {
  name                    = "nexusshield-onprem-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "onprem_subnet" {
  name                     = "nexusshield-onprem-subnet"
  ip_cidr_range            = "10.0.0.0/20"
  region                   = var.primary_interconnect_region
  network                  = google_compute_network.onprem_vpc.id
  private_ip_google_access = true
}

# ===== VAULT FOR SSH KEY MANAGEMENT =====

# Note: Vault setup assumes pre-existing Vault instance
# This section demonstrates the Terraform for configuring Vault

# SSH secret engine
resource "vault_ssh_secret_backend" "nexusshield" {
  path = "ssh"
}

# SSH certificate role for on-premises access
resource "vault_ssh_secret_backend_ca" "nexusshield" {
  backend              = vault_ssh_secret_backend.nexusshield.path
  generate_signing_key = true
}

# SSH role for on-premises systems (30-day key rotation)
resource "vault_ssh_secret_backend_role" "onprem_deployer" {
  name                    = "onprem-deployer"
  backend                 = vault_ssh_secret_backend.nexusshield.path
  key_type                = "ca"
  certificate_authorities = vault_ssh_secret_backend_ca.nexusshield.public_key
  allowed_users           = "ubuntu,ec2-user,root"
  ttl                     = var.ssh_key_rotation_days * 86400  # Convert days to seconds
  max_ttl                 = (var.ssh_key_rotation_days * 2) * 86400
  default_critical_options = {
    "force-command" = "no-pty"
  }
}

# ===== KEY ROTATION AUTOMATION =====
# Cloud Scheduler job to trigger key rotation

resource "google_cloud_scheduler_job" "ssh_key_rotation" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  name        = "nexusshield-ssh-key-rotation"
  description = "Rotate SSH keys for on-premises access"
  schedule    = "0 2 * * 0"  # Every Sunday at 2 AM UTC
  time_zone   = "UTC"
  region      = var.primary_interconnect_region

  http_target {
    uri        = "https://vault.nexusshield.cloud/v1/ssh/issue/onprem-deployer"
    http_method = "POST"
    headers = {
      "X-Vault-Token" = var.vault_token  # Should be stored in Secret Manager
    }
  }

  depends_on = [google_cloud_scheduler_job.ssh_key_rotation]
}

# ===== FIREWALL RULES FOR ON-PREMISES ACCESS =====

resource "google_compute_firewall" "allow_onprem_ssh" {
  name    = "nexusshield-allow-onprem-ssh"
  network = google_compute_network.onprem_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]  # SSH
  }

  source_ranges = ["10.40.0.0/16"]  # On-premises CIDR
  target_tags   = ["nexusshield-onprem-accessible"]
}

resource "google_compute_firewall" "allow_onprem_api" {
  name    = "nexusshield-allow-onprem-api"
  network = google_compute_network.onprem_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443"]  # HTTPS
  }

  source_ranges = ["10.40.0.0/16"]  # On-premises CIDR
  target_tags   = ["nexusshield-api"]
}

# ===== MONITORING AND ALERTS =====

resource "google_monitoring_alert_policy" "interconnect_down" {
  count = var.onprem_redundancy_enabled ? 1 : 0

  display_name = "Cloud Interconnect Down - Failover to VPN"
  combiner     = "OR"

  conditions {
    display_name = "Interconnect status != UP"

    condition_threshold {
      filter          = "resource.type=\"compute.googleapis.com/InterconnectAttachment\" AND metric.type=\"compute.googleapis.com/interconnect_attachment/operational_status\" AND resource.labels.name=~\".*primary-interconnect.*\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1.0
      
      aggregations {
        alignment_period  = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []  # Add notification channel IDs
}

# ===== OUTPUTS =====

output "primary_interconnect_name" {
  value       = try(google_compute_interconnect_attachment.primary_onprem[0].name, "")
  description = "Primary Cloud Interconnect attachment name"
}

output "backup_vpn_gateway_ip" {
  value       = try(google_compute_vpn_gateway.onprem_backup[0].vpn_interfaces[0].ip_address, "")
  description = "Backup VPN gateway IP address"
}

output "ssh_key_rotation_schedule" {
  value       = "Every Sunday at 2 AM UTC (${var.ssh_key_rotation_days}-day rotation cycle)"
  description = "SSH key rotation schedule"
}

output "vault_ssh_role" {
  value       = try(vault_ssh_secret_backend_role.onprem_deployer.name, "")
  description = "Vault SSH secret backend role for on-premises access"
}

output "redundancy_status" {
  value       = var.onprem_redundancy_enabled
  description = "On-premises redundancy enabled"
}
