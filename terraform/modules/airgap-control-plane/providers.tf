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

# Provider blocks removed: provider configuration is expected to be supplied
# by the root module. Empty provider blocks are deprecated and cause
# redundant-provider warnings in child modules. Consumers should pass
# provider configurations when calling this module if custom provider
# settings are required.
