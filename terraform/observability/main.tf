// Terraform module scaffold for Observability stack
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.namespace
  }
}

// TODO: Add HelmRelease or helm_release resources for kube-prometheus-stack, grafana, and loki
