/**
 * VPC Networking Module - Outputs
 */

output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "primary_subnet_id" {
  description = "Primary subnet ID"
  value       = google_compute_subnetwork.primary.id
}

output "primary_subnet_name" {
  description = "Primary subnet name"
  value       = google_compute_subnetwork.primary.name
}

output "cloud_run_subnet_id" {
  description = "Cloud Run connector subnet ID"
  value       = google_compute_subnetwork.cloud_run_connector.id
}

output "cloud_run_subnet_name" {
  description = "Cloud Run connector subnet name"
  value       = google_compute_subnetwork.cloud_run_connector.name
}

output "vpc_connector_id" {
  description = "VPC connector ID"
  value       = google_vpc_access_connector.main.id
}

output "vpc_connector_name" {
  description = "VPC connector name (use in Cloud Run config)"
  value       = google_vpc_access_connector.main.name
}

output "private_service_connection_id" {
  description = "Private service connection ID"
  value       = google_service_networking_connection.private_vpc_connection.id
}

output "router_id" {
  description = "Cloud Router ID (if NAT enabled)"
  value       = try(google_compute_router.main[0].id, null)
}

output "nat_id" {
  description = "Cloud NAT ID (if NAT enabled)"
  value       = try(google_compute_router_nat.main[0].id, null)
}
