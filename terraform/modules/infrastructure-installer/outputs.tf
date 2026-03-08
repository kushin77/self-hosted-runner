output "minio_enabled" {
  description = "Whether MinIO is deployed"
  value       = var.enable_minio
}

output "minio_endpoint" {
  description = "MinIO service endpoint"
  value       = var.enable_minio ? module.minio[0].minio_endpoint : null
}

output "minio_console_endpoint" {
  description = "MinIO web console endpoint"
  value       = var.enable_minio ? module.minio[0].minio_console_endpoint : null
}

output "harbor_enabled" {
  description = "Whether Harbor is deployed"
  value       = var.enable_harbor
}

output "harbor_url" {
  description = "Harbor web UI URL"
  value       = var.enable_harbor ? module.harbor[0].harbor_url : null
}

output "harbor_registry_url" {
  description = "Harbor Docker registry endpoint"
  value       = var.enable_harbor ? module.harbor[0].harbor_registry_url : null
}

output "harbor_admin_user" {
  description = "Harbor admin username"
  value       = var.enable_harbor ? module.harbor[0].harbor_admin_user : null
}

output "observability_enabled" {
  description = "Whether observability stack is deployed"
  value       = var.enable_observability
}

output "prometheus_url" {
  description = "Prometheus web UI URL"
  value       = var.enable_observability ? "http://prometheus.${var.base_domain}" : null
}

output "grafana_url" {
  description = "Grafana web UI URL"
  value       = var.enable_observability ? "http://grafana.${var.base_domain}" : null
}

output "alertmanager_url" {
  description = "AlertManager web UI URL"
  value       = var.enable_observability ? "http://alertmanager.${var.base_domain}" : null
}

output "vault_enabled" {
  description = "Whether Vault is deployed"
  value       = var.enable_vault
}

output "vault_url" {
  description = "Vault API URL"
  value       = var.enable_vault ? module.vault[0].vault_url : null
}

output "environment" {
  description = "Deployed environment"
  value       = var.environment
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "deployment_summary" {
  description = "Summary of deployed components"
  value = {
    minio        = var.enable_minio
    harbor       = var.enable_harbor
    observability = var.enable_observability
    vault        = var.enable_vault
    environment  = var.environment
    region       = var.region
    timestamp    = timeadd(timestamp(), "0s")  # Deployment timestamp
  }
}

output "gcp_secret_manager_paths" {
  description = "GCP Secret Manager paths for all secrets"
  value = merge(
    var.enable_minio ? {
      minio_access_key = module.minio[0].minio_access_key_secret
      minio_secret_key = module.minio[0].minio_secret_key_secret
    } : {},
    var.enable_harbor ? {
      harbor_admin_password = module.harbor[0].harbor_admin_password_secret
    } : {},
    var.enable_observability ? {
      grafana_admin_password = module.observability[0].grafana_admin_password_secret
    } : {},
    var.enable_vault ? {
      vault_unseal_key = module.vault[0].vault_unseal_key_secret
      vault_root_token = module.vault[0].vault_root_token_secret
    } : {}
  )
  sensitive = true
}

output "ingress_controller_status" {
  description = "Status of nginx ingress controller"
  value       = helm_release.ingress_nginx.status
}

output "smoke_test_status" {
  description = "Integration smoke test result"
  value = {
    job_name = kubernetes_job_v1.integration_smoke_test.metadata[0].name
    namespace = kubernetes_job_v1.integration_smoke_test.metadata[0].namespace
  }
}
