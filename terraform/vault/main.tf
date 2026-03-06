// Terraform module scaffold for Vault
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

resource "kubernetes_namespace" "vault" {
  metadata {
    name = var.namespace
  }
}

// TODO: Add Helm release for official Vault chart and resources for auto-unseal.
# Sub-module for Vault AppRole provisioning
# This lives separately from the main runner terraform configuration to
# avoid requiring unrelated input variables.

variable "vault_addr" {
  type        = string
  description = "Address of the Vault server (e.g. https://vault.example.com)"
}

provider "vault" {
  address = var.vault_addr
}

resource "vault_approle_auth_backend" "provisioner" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "provisioner_role" {
  backend        = vault_approle_auth_backend.provisioner.path
  role_name      = "provisioner-worker"
  token_policies = ["provisioner-worker"]
  token_ttl      = "1h"
}

resource "vault_approle_auth_backend_role_id" "role_id" {
  backend   = vault_approle_auth_backend.provisioner.path
  role_name = vault_approle_auth_backend_role.provisioner_role.role_name
}

resource "vault_approle_auth_backend_role_secret_id" "secret_id" {
  backend       = vault_approle_auth_backend.provisioner.path
  role_name     = vault_approle_auth_backend_role.provisioner_role.role_name
  secret_id_ttl = "24h"
}

output "vault_app_role_id" {
  value = vault_approle_auth_backend_role_id.role_id.role_id
}

output "vault_app_secret_id" {
  value = vault_approle_auth_backend_role_secret_id.secret_id.secret_id
}
