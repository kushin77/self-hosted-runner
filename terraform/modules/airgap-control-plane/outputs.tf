output "namespace_name" {
  description = "Name of the created Kubernetes namespace"
  value       = kubernetes_namespace_v1.airgap_control_plane.metadata[0].name
}

output "namespace_id" {
  description = "ID of the created Kubernetes namespace"
  value       = kubernetes_namespace_v1.airgap_control_plane.id
}

output "egress_policy_name" {
  description = "Name of the egress network policy"
  value       = kubernetes_network_policy_v1.airgap_egress_policy.metadata[0].name
}

output "egress_policy_id" {
  description = "ID of the egress network policy"
  value       = kubernetes_network_policy_v1.airgap_egress_policy.id
}
