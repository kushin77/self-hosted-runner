// Terraform module for deploying air-gapped RunnerCloud control plane
// This is a skeleton; resources should be added per customer requirements.

variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster"
}

variable "namespace" {
  type        = string
  default     = "runnercloud"
  description = "Kubernetes namespace to deploy components into"
}

// example of creating namespace
resource "kubernetes_namespace" "airgap" {
  metadata {
    name = var.namespace
  }
}

// network policy placeholder
resource "kubernetes_network_policy" "egress" {
  metadata {
    name      = "deny-egress-by-default"
    namespace = kubernetes_namespace.airgap.metadata[0].name
  }

  spec {
    pod_selector = {}
    policy_types = ["Egress"]
    egress {
      to {
        namespace_selector = {}
      }
      ports {
        protocol = "TCP"
        port     = 443
      }
    }
  }
}
