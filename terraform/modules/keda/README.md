# KEDA + Prometheus Adapter Terraform Module

This module installs KEDA and a Prometheus metrics adapter via Helm releases. It expects a configured Kubernetes provider or Helm provider in the root module.

Usage example:

module "keda" {
  source = "../../modules/keda"
  namespace = "keda"
}

Notes:
- This module uses the `helm` provider; configure provider auth (kubeconfig, controller) in the root.
- Chart versions are configurable via variables.
