terraform {
  required_version = ">= 1.0"
  required_providers {
    helm       = ">= 2.0"
    kubernetes = ">= 2.0"
    google     = ">= 4.0"
  }
}

# MinIO Module
module "minio" {
  count  = var.enable_minio ? 1 : 0
  source = "../minio"

  namespace              = "artifacts"
  replicas              = var.minio_replicas
  storage_capacity      = var.minio_storage_capacity
  storage_class         = var.minio_storage_class
  gcp_secret_project    = var.gsm_project_id
  access_key_secret_name = "minio-access-key-${var.environment}"
  secret_key_secret_name = "minio-secret-key-${var.environment}"
  minio_image_tag       = var.minio_image_tag
  enable_smoke_test     = true
}

# Harbor Module
module "harbor" {
  count  = var.enable_harbor ? 1 : 0
  source = "../harbor"

  namespace              = "harbor"
  hostname               = "harbor.${var.base_domain}"
  gcp_secret_project     = var.gsm_project_id
  admin_password_secret  = "harbor-admin-password-${var.environment}"
  database_password_secret = "harbor-db-password-${var.environment}"
  redis_password_secret  = "harbor-redis-password-${var.environment}"
  storage_type           = "gcs"
  gcs_bucket             = "harbor-storage-${var.gcp_project_id}-${var.environment}"
  enable_trivy           = true
  harbor_image_tag       = var.harbor_image_tag
  enable_smoke_test      = true
}

# Observability Stack (Prometheus + Grafana + AlertManager)
module "observability" {
  count  = var.enable_observability ? 1 : 0
  source = "../observability"

  namespace                = "observability"
  prometheus_retention_days = var.prometheus_retention_days
  prometheus_storage_size  = var.prometheus_storage_size
  grafana_admin_password_secret = "grafana-admin-password-${var.environment}"
  gcp_secret_project       = var.gsm_project_id
  enable_persistent_storage = true
  enable_alerting          = true
  enable_smoke_test        = true
}

# Vault Module (optional, for secrets management)
module "vault" {
  count  = var.enable_vault ? 1 : 0
  source = "../vault"

  namespace                = "vault"
  unseal_key_secret        = "vault-unseal-key-${var.environment}"
  root_token_secret        = "vault-root-token-${var.environment}"
  gcp_secret_project       = var.gsm_project_id
  storage_backend_bucket   = "vault-storage-${var.gcp_project_id}-${var.environment}"
  enable_tls               = true
  enable_smoke_test        = true
}

# Ingress & Networking Setup
resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_chart_version
  namespace        = kubernetes_namespace.ingress.metadata[0].name
  create_namespace = false

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  timeout = 300
  wait    = true
}

# End-to-End Smoke Test
resource "kubernetes_job_v1" "integration_smoke_test" {
  depends_on = [
    module.minio,
    module.harbor,
    module.observability,
    module.vault
  ]

  metadata {
    name      = "infrastructure-installer-smoke-test"
    namespace = "default"
  }

  spec {
    template {
      metadata {
        labels = {
          app = "infrastructure-installer-smoke-test"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.smoke_test.metadata[0].name
        restart_policy       = "Never"

        container {
          name  = "smoke-test"
          image = "curlimages/curl:latest"

          env {
            name  = "MINIO_ENABLED"
            value = var.enable_minio ? "true" : "false"
          }

          env {
            name  = "HARBOR_ENABLED"
            value = var.enable_harbor ? "true" : "false"
          }

          env {
            name  = "OBSERVABILITY_ENABLED"
            value = var.enable_observability ? "true" : "false"
          }

          command = ["/bin/sh"]
          args = [
            "-c",
            file("${path.module}/scripts/smoke-test.sh")
          ]

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1"
              memory = "512Mi"
            }
          }
        }
      }
    }

    backoff_limit = 2
  }

  wait_for_completion = true
}

resource "kubernetes_service_account_v1" "smoke_test" {
  metadata {
    name      = "infrastructure-installer-smoke-test"
    namespace = "default"
  }
}
