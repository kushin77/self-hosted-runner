// Conditional VPC peering and reserved range for Google-managed services
// Enable by setting `enable_vpc_peering = true` when running Terraform.

variable "enable_vpc_peering" {
  description = "Enable VPC peering to Google-managed services (Private Service Connect)"
  type        = bool
  default     = false
}

variable "psc_range_name" {
  description = "Name for the reserved global address range used for VPC peering"
  type        = string
  default     = null
}

variable "psc_prefix_length" {
  description = "Prefix length for the reserved peering range (e.g. 16)"
  type        = number
  default     = 16
}

locals {
  effective_psc_range_name = var.psc_range_name == null ? "${local.env_prefix}-psc-range" : var.psc_range_name
}

resource "google_compute_global_address" "psc_range" {
  count         = var.enable_vpc_peering ? 1 : 0
  name          = local.effective_psc_range_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psc_prefix_length
  network       = google_compute_network.vpc.self_link
  project       = var.gcp_project
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.enable_vpc_peering ? 1 : 0
  network                 = google_compute_network.vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psc_range[0].name]

  depends_on = [
    google_compute_global_address.psc_range
  ]
}

output "vpc_peering_enabled" {
  value = var.enable_vpc_peering
}
