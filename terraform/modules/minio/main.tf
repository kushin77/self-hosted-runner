terraform {
  required_version = ">= 1.0"
  required_providers {
    helm       = ">= 2.0"
    kubernetes = ">= 2.0"
    google     = ">= 4.0"
  }
}

# Data source: Get credentials from GCP Secret Manager
data "google_secret_manager_secret_version" "minio_access_key" {
  secret      = var.access_key_secret_name
  project     = var.gcp_secret_project
  version     = "latest"
}

data "google_secret_manager_secret_version" "minio_secret_key" {
  secret      = var.secret_key_secret_name
  project     = var.gcp_secret_project
  version     = "latest"
}

# Helm Release: MinIO Operator (stable)
resource "helm_release" "minio_operator" {
  name             = "minio-operator"
  repository       = "https://operator.min.io"
  chart            = "minio-operator"
  version          = var.operator_chart_version
  namespace        = var.namespace
  create_namespace = true

  set {
    name  = "image.tag"
    value = var.operator_image_tag  # Pinned for immutability
  }

  set {
    name  = "replicas"
    value = 2
  }

  timeout = 600
  wait    = true

  lifecycle {
    ignore_changes = [version]  # Manual upgrades only
  }
}

# Helm Release: MinIO Tenant
resource "helm_release" "minio_tenant" {
  depends_on = [helm_release.minio_operator]

  name             = "minio-tenant"
  repository       = "https://minio.github.io/helm-charts"
  chart            = "minio"
  version          = var.minio_chart_version
  namespace        = var.namespace
  create_namespace = false

  values = [
    templatefile("${path.module}/helm-values.tpl", {
      replicas           = var.replicas
      image_tag          = var.minio_image_tag
      storage_capacity   = var.storage_capacity
      storage_class      = var.storage_class
      tls_enabled        = var.tls_enabled
      tls_cert_secret    = var.tls_cert_secret_name
      access_key         = sensitive(data.google_secret_manager_secret_version.minio_access_key.secret_data)
      secret_key         = sensitive(data.google_secret_manager_secret_version.minio_secret_key.secret_data)
    })
  ]

  dynamic "set" {
    for_each = var.additional_helm_values
    content {
      name  = set.key
      value = set.value
    }
  }

  timeout = 600
  wait    = true

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [version]
  }
}

# Smoke Test Job
resource "kubernetes_job_v1" "minio_smoke_test" {
  count = var.enable_smoke_test ? 1 : 0

  depends_on = [helm_release.minio_tenant]

  metadata {
    name      = "minio-smoke-test"
    namespace = var.namespace
  }

  spec {
    template {
      metadata {
        labels = {
          app = "minio-smoke-test"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.minio_smoke[0].metadata[0].name
        restart_policy       = "Never"

        container {
          name  = "minio-client"
          image = "minio/mc:latest"

          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio_creds[0].metadata[0].name
                key  = "access_key"
              }
            }
          }

          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio_creds[0].metadata[0].name
                key  = "secret_key"
              }
            }
          }

          command = ["/bin/sh"]
          args = [
            "-c",
            <<-EOT
              set -e
              mc alias set minio http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
              mc version minio
              mc ls minio/
              echo "✅ MinIO smoke test PASSED"
            EOT
          ]

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }

    backoff_limit = 3
  }

  wait_for_completion = var.enable_smoke_test
}

# Service Account for smoke test
resource "kubernetes_service_account_v1" "minio_smoke" {
  count = var.enable_smoke_test ? 1 : 0

  metadata {
    name      = "minio-smoke-test"
    namespace = var.namespace
  }
}

# Secret with MinIO credentials (for smoke test)
resource "kubernetes_secret_v1" "minio_creds" {
  count = var.enable_smoke_test ? 1 : 0

  metadata {
    name      = "minio-credentials"
    namespace = var.namespace
  }

  data = {
    access_key = data.google_secret_manager_secret_version.minio_access_key.secret_data
    secret_key = data.google_secret_manager_secret_version.minio_secret_key.secret_data
  }

  type = "Opaque"
}
