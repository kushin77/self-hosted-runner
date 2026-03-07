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

# Configure Kubernetes provider
provider "kubernetes" {
  # Configuration is inherited from kubeconfig context or
  # explicitly set via clusters variable
}

# Configure Helm provider (inherits from Kubernetes provider)
provider "helm" {
  # Helm provider automatically inherits Kubernetes configuration
}
