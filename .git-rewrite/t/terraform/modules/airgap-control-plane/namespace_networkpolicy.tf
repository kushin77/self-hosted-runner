// Namespace and NetworkPolicy for air-gapped control plane
resource "kubernetes_namespace" "airgap_control_plane" {
  metadata {
    name = var.namespace_name
    labels = var.namespace_labels
  }
}

resource "kubernetes_network_policy" "airgap_egress_policy" {
  metadata {
    name      = "airgap-control-plane-egress"
    namespace = kubernetes_namespace.airgap_control_plane.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = var.allowed_registry_cidr
        }
      }
    }

    egress {
      to {
        ip_block {
          cidr = var.allowed_collector_cidr
        }
      }
    }
  }
}
