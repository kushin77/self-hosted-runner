terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

# Kubernetes Deployment for managed-auth service
resource "kubernetes_deployment" "managed_auth" {
  metadata {
    name      = "managed-auth"
    namespace = var.namespace

    labels = {
      app       = "managed-auth"
      version   = var.image_tag
      component = "control-plane"
    }
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        app = "managed-auth"
      }
    }

    template {
      metadata {
        labels = {
          app = "managed-auth"
        }

        annotations = {
          "prometheus.io/scrape" = var.enable_monitoring ? "true" : "false"
          "prometheus.io/port"   = "9091"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.managed_auth.metadata[0].name

        container {
          name              = "managed-auth"
          image             = "${var.image_repository}:${var.image_tag}"
          image_pull_policy = "IfNotPresent"

          ports {
            container_port = var.port
            name           = "http"
            protocol       = "TCP"
          }

          ports {
            container_port = 9091
            name           = "metrics"
            protocol       = "TCP"
          }

          env {
            name  = "PORT"
            value = tostring(var.port)
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "VAULT_ADDR"
            value = var.vault_addr
          }

          env {
            name  = "VAULT_NAMESPACE"
            value = var.vault_namespace
          }

          env {
            name  = "VAULT_AUTH_METHOD"
            value = var.vault_auth_method
          }

          env {
            name  = "DATABASE_URL"
            value = "postgresql://${var.database_user}:${var.database_password}@${var.database_host}:${var.database_port}/${var.database_name}?sslmode=require"
          }

          env {
            name  = "ENABLE_METRICS"
            value = var.enable_monitoring ? "true" : "false"
          }

          env {
            name  = "ENABLE_TRACING"
            value = var.enable_tracing ? "true" : "false"
          }

          env {
            name  = "TOKEN_TTL_MAX"
            value = tostring(var.token_ttl_max)
          }

          env {
            name  = "HEARTBEAT_INTERVAL"
            value = tostring(var.heartbeat_interval)
          }

          env {
            name  = "HEARTBEAT_TIMEOUT"
            value = tostring(var.heartbeat_timeout)
          }

          env {
            name  = "ENABLE_MTLS"
            value = var.enable_mtls ? "true" : "false"
          }

          env {
            name  = "LOG_LEVEL"
            value = "info"
          }

          # Health check
          liveness_probe {
            http_get {
              path   = "/health"
              port   = var.port
              scheme = "HTTP"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path   = "/health"
              port   = var.port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 2
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          volume_mount {
            name       = "cache"
            mount_path = "/app/cache"
          }
        }

        # Pod security policy
        security_context {
          fsGroup = 1000
        }

        volume {
          name = "tmp"
          empty_dir {
            medium = "Memory"
          }
        }

        volume {
          name = "cache"
          empty_dir {}
        }

        # Pod disruption budget for high availability
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["managed-auth"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
              weight = 100
            }
          }
        }
      }
    }
  }
}

# Service account for managed-auth
resource "kubernetes_service_account" "managed_auth" {
  metadata {
    name      = "managed-auth"
    namespace = var.namespace

    labels = {
      app = "managed-auth"
    }
  }
}

# Cluster role for Vault authentication
resource "kubernetes_cluster_role" "managed_auth" {
  metadata {
    name = "managed-auth"
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts/token"]
    verbs      = ["create"]
  }
}

# Cluster role binding
resource "kubernetes_cluster_role_binding" "managed_auth" {
  metadata {
    name = "managed-auth"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.managed_auth.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.managed_auth.metadata[0].name
    namespace = var.namespace
  }
}

# Kubernetes Service
resource "kubernetes_service" "managed_auth" {
  metadata {
    name      = "managed-auth"
    namespace = var.namespace

    labels = {
      app = "managed-auth"
    }
  }

  spec {
    type = "LoadBalancer"

    port {
      name        = "http"
      port        = 443
      target_port = var.port
      protocol    = "TCP"
    }

    port {
      name        = "metrics"
      port        = 9091
      target_port = 9091
      protocol    = "TCP"
    }

    selector = {
      app = "managed-auth"
    }

    session_affinity = "ClientIP"
  }
}

# Pod Disruption Budget for availability
resource "kubernetes_pod_disruption_budget" "managed_auth" {
  metadata {
    name      = "managed-auth"
    namespace = var.namespace
  }

  spec {
    min_available = 2

    selector {
      match_labels = {
        app = "managed-auth"
      }
    }
  }
}

# Network Policy to restrict traffic
resource "kubernetes_network_policy" "managed_auth" {
  metadata {
    name      = "managed-auth"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = "managed-auth"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from runners
    ingress {
      from {
        pod_selector {
          match_labels = {
            component = "runner"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = var.port
      }
    }

    # Allow ingress from Prometheus
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "9091"
      }
    }

    # Allow DNS egress
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow egress to Vault
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "vault"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "8200"
      }
    }

    # Allow egress to PostgreSQL
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgresql"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}
