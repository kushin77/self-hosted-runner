output "runner_template_self_link" {
  value       = google_compute_instance_template.runner_template.self_link
  description = "Self-link for the hardened instance template"
}

output "runner_template_name" {
  value       = google_compute_instance_template.runner_template.name
  description = "Instance template name that can be referenced by instance groups or deployment managers"
}

output "runner_network_tags" {
  value       = local.runner_tags
  description = "Tags used by firewall resources to isolate the tenant"
}

output "ingress_firewall_name" {
  value       = google_compute_firewall.runner_ingress_deny.name
  description = "The deny-all ingress firewall that reinforces perimeter control"
}

output "egress_firewall_name" {
  value       = google_compute_firewall.runner_egress_deny.name
  description = "The deny-all egress firewall (complemented by allow rules)"
}

output "effective_egress_destinations" {
  value       = local.effective_allowed_egress_cidrs
  description = "CIDRs that remain reachable (metadata plus approved registries)"
}