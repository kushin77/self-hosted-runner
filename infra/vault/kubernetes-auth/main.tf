// Vault Kubernetes Auth Method Setup (for Phase P4 control-plane)
// This enables Kubernetes pods to authenticate to Vault without static credentials

terraform {
  required_version = ">= 1.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

variable "vault_addr" {
  type    = string
  default = "https://vault.example.local"
}

variable "kubernetes_host" {
  type    = string
  description = "Kubernetes API server URL (e.g., https://kubernetes.default.svc)"
  default = "https://kubernetes.default.svc"
}

variable "kubernetes_ca_cert" {
  type    = string
  description = "Kubernetes CA certificate (read from /var/run/secrets/kubernetes.io/serviceaccount/ca.crt in pod)"
}

variable "kubernetes_token" {
  type    = string
  sensitive = true
  description = "Kubernetes service account token (read from /var/run/secrets/kubernetes.io/serviceaccount/token in pod)"
}

// Enable Kubernetes auth method
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "auth/kubernetes"
}

// Configure the Kubernetes auth backend
resource "vault_kubernetes_auth_backend_config" "example" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = var.kubernetes_ca_cert
  token_reviewer_jwt = var.kubernetes_token
}

// Create a role for the control-plane-envoy namespace/service account
resource "vault_kubernetes_auth_backend_role" "control_plane_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "control-plane-role"
  bound_service_account_names      = ["control-plane-envoy"]
  bound_service_account_namespaces = ["control-plane"]

  token_ttl       = 3600
  token_max_ttl   = 86400
  token_policies  = ["control-plane"]
}

// Example Vault policy for control-plane runners
resource "vault_policy" "control_plane" {
  name = "control-plane"

  policy = <<EOH
path "pki/issue/control-plane-role" {
  capabilities = ["create", "update"]
}

path "secret/data/runners/control-plane/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOH
}

output "kubernetes_auth_path" {
  value       = vault_auth_backend.kubernetes.path
  description = "Path to the Kubernetes auth method"
}

output "control_plane_role_name" {
  value       = vault_kubernetes_auth_backend_role.control_plane_role.role_name
  description = "Name of the Vault role for control-plane pods"
}
