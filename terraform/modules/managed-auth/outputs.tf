output "service_url" {
  description = "Public service URL"
  value       = "https://${data.kubernetes_service.managed_auth.status[0].load_balancer[0].ingress[0].hostname}:443"
}

output "service_endpoint" {
  description = "Internal Kubernetes service endpoint"
  value       = "managed-auth.${var.namespace}.svc.cluster.local"
}

output "service_port" {
  description = "Service port"
  value       = var.port
}

output "deployment_name" {
  description = "Kubernetes deployment name"
  value       = kubernetes_deployment.managed_auth.metadata[0].name
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = var.namespace
}

output "service_account_name" {
  description = "Kubernetes service account name"
  value       = kubernetes_service_account.managed_auth.metadata[0].name
}

output "metrics_port" {
  description = "Prometheus metrics port"
  value       = 9091
}

output "metrics_endpoint" {
  description = "Prometheus metrics endpoint"
  value       = "http://managed-auth.${var.namespace}.svc.cluster.local:9091/metrics"
}

output "replica_count" {
  description = "Number of pod replicas"
  value       = var.replica_count
}

output "cluster_role_name" {
  description = "Kubernetes cluster role for Vault auth"
  value       = kubernetes_cluster_role.managed_auth.metadata[0].name
}

# Data source to get service info
data "kubernetes_service" "managed_auth" {
  metadata {
    name      = kubernetes_service.managed_auth.metadata[0].name
    namespace = kubernetes_service.managed_auth.metadata[0].namespace
  }
  depends_on = [kubernetes_service.managed_auth]
}
