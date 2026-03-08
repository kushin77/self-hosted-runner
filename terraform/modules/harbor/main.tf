terraform {
  required_version = ">= 1.0"
  required_providers {
    helm       = ">= 2.0"
    kubernetes = ">= 2.0"
    google     = ">= 4.0"
  }
}

# Data sources: Fetch credentials from GCP Secret Manager
data "google_secret_manager_secret_version" "harbor_admin_password" {
  secret  = var.admin_password_secret
  project = var.gcp_secret_project
  version = "latest"
}

data "google_secret_manager_secret_version" "harbor_db_password" {
  secret  = var.database_password_secret
  project = var.gcp_secret_project
  version = "latest"
}

data "google_secret_manager_secret_version" "harbor_redis_password" {
  secret  = var.redis_password_secret
  project = var.gcp_secret_project
  version = "latest"
}

# Helm Release: Harbor
resource "helm_release" "harbor" {
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = var.harbor_chart_version
  namespace        = var.namespace
  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values.tpl", {
      hostname            = var.hostname
      image_tag           = var.harbor_image_tag
      trivy_enabled       = var.enable_trivy
      trivy_skip_update   = var.trivy_skip_update
      admin_password      = sensitive(data.google_secret_manager_secret_version.harbor_admin_password.secret_data)
      db_password         = sensitive(data.google_secret_manager_secret_version.harbor_db_password.secret_data)
      redis_password      = sensitive(data.google_secret_manager_secret_version.harbor_redis_password.secret_data)
      gcs_bucket          = var.gcs_bucket
      gcs_project         = var.gcp_secret_project
      storage_type        = var.storage_type
    })
  ]

  dynamic "set" {
    for_each = var.additional_helm_values
    content {
      name  = set.key
      value = set.value
    }
  }

  timeout = 900
  wait    = true

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [version]
  }
}

# Smoke Test Job
resource "kubernetes_job_v1" "harbor_smoke_test" {
  count      = var.enable_smoke_test ? 1 : 0
  depends_on = [helm_release.harbor]

  metadata {
    name      = "harbor-smoke-test"
    namespace = var.namespace
  }

  spec {
    template {
      metadata {
        labels = {
          app = "harbor-smoke-test"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.harbor_smoke[0].metadata[0].name
        restart_policy       = "Never"

        container {
          name  = "harbor-client"
          image = "curlimages/curl:latest"

          env {
            name  = "HARBOR_URL"
            value = "http://harbor:80"
          }

          env {
            name = "ADMIN_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.harbor_creds[0].metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.harbor_creds[0].metadata[0].name
                key  = "password"
              }
            }
          }

          command = ["/bin/sh"]
          args = [
            "-c",
            <<-EOT
              set -e
              curl -sS $HARBOR_URL/api/v2.0/systeminfo || exit 1
              curl -sS -u "$ADMIN_USER:$ADMIN_PASSWORD" $HARBOR_URL/api/v2.0/projects || exit 1
              echo "✅ Harbor smoke test PASSED"
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

# Service Account and credentials
resource "kubernetes_service_account_v1" "harbor_smoke" {
  count = var.enable_smoke_test ? 1 : 0

  metadata {
    name      = "harbor-smoke-test"
    namespace = var.namespace
  }
}

resource "kubernetes_secret_v1" "harbor_creds" {
  count = var.enable_smoke_test ? 1 : 0

  metadata {
    name      = "harbor-credentials"
    namespace = var.namespace
  }

  data = {
    username = base64encode("admin")
    password = base64encode(data.google_secret_manager_secret_version.harbor_admin_password.secret_data)
  }

  type = "Opaque"
}
