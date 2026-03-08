// Vault PKI scaffold (example)

provider "vault" {
  address = var.vault_addr
}

variable "vault_addr" {
  type    = string
  default = "https://vault.example.local"
}

// Enable PKI mount (example)
resource "vault_mount" "pki" {
  path = "pki"
  type = "pki"
}

// Tune TTLs for issued certs
resource "vault_mount_tune" "pki_tune" {
  path                  = vault_mount.pki.path
  max_lease_ttl_seconds = 31536000
}

// Create a role that allows issuing certs for control-plane
resource "vault_pki_secret_backend_role" "control_plane_role" {
  backend          = vault_mount.pki.path
  name             = "control-plane-role"
  allow_any_name   = false
  allowed_domains  = ["control-plane.example.local"]
  allow_subdomains = true
  max_ttl          = "72h"
}

// Note: Create an intermediate/root CA or configure Vault PKI properly before issuing certs.
