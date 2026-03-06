// Terraform module scaffold for MinIO (helm release example)
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

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "kubernetes_namespace" "minio" {
  metadata {
    name = var.namespace
  }
}

// Example helm_release: assumes chart is located at `deploy/minio` in the repo
// Adapt values and repository for production usage.
resource "helm_release" "minio" {
  name       = var.release_name
  namespace  = kubernetes_namespace.minio.metadata[0].name
  chart      = "./deploy/minio"
  create_namespace = false
  values = [file("./deploy/minio/values.yaml")]
}
