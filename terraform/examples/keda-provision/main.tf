variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0"
    }
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

provider "helm" {
  kubernetes {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

module "keda" {
  source    = "../../modules/keda"
  namespace = "keda"
  providers = {
    kubernetes = kubernetes
    helm       = helm
  }
}
