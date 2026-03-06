// Terraform module scaffold for Harbor (helm release example)
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "harbor" {
  name      = var.release_name
  namespace = kubernetes_namespace.harbor.metadata[0].name
  chart     = "./deploy/harbor"
  values    = [file("./deploy/harbor/values.yaml")]
}
