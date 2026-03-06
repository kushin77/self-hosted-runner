// Terraform module scaffold for Harbor
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.namespace
  }
}

// TODO: Add Helm release resource pointing at the official Harbor chart
