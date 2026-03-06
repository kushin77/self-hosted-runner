// Terraform module scaffold for MinIO
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

resource "kubernetes_namespace" "minio" {
  metadata {
    name = var.namespace
  }
}

// Further resources (statefulset, svc, pvc) to be added in follow-ups
