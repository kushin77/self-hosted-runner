terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10"
    }
  }
}

# This test configuration demonstrates how to use the airgap-control-plane module
module "airgap_control_plane_test" {
  source = "../"

  # Basic configuration
  namespace_name = "airgap-test"
  cluster_name   = "test-cluster"

  # Network policies - restrict to test ranges
  allowed_registry_cidr  = "10.0.0.0/24"
  allowed_collector_cidr = "10.0.1.0/24"

  # Helm configuration
  helm_release_name  = "airgap-test"
  helm_chart_version = "1.0.0"

  # Image preload
  create_image_storage_pvc = true
  image_storage_size       = "20Gi" # Smaller for testing
  storage_class_name       = "standard"

  # Collector
  collector_enabled = true

  # Registry mirror - optional for testing
  registry_mirror_enabled = false

  # Labels for testing
  namespace_labels = {
    "test-run"    = "true"
    "environment" = "test"
  }
}

# Output test results
output "test_namespace" {
  value = module.airgap_control_plane_test.namespace_name
}

output "test_egress_policy" {
  value = module.airgap_control_plane_test.egress_policy_name
}
