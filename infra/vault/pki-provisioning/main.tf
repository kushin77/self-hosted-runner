// Vault PKI Root CA & Intermediate CA Provisioning Module
// This module sets up a production-grade PKI chain in Vault

terraform {
  required_version = ">= 1.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "vault_addr" {
  type    = string
  default = "https://vault.example.local"
}

variable "root_ca_common_name" {
  type    = string
  default = "Phase P4 Root CA"
}

variable "intermediate_ca_common_name" {
  type    = string
  default = "Phase P4 Intermediate CA"
}

variable "ttl" {
  type    = string
  default = "87600h"  # 10 years for root, adjust as needed
}

variable "max_ttl" {
  type    = string
  default = "876000h"
}

// Enable PKI secret engines
resource "vault_mount" "pki_root" {
  path        = "pki"
  type        = "pki"
  description = "Phase P4 Root PKI"

  max_lease_ttl_seconds = 315360000  # 10 years
}

resource "vault_mount" "pki_intermediate" {
  path        = "pki_int"
  type        = "pki"
  description = "Phase P4 Intermediate PKI"

  max_lease_ttl_seconds = 157680000  # 5 years
}

// Configure root CA
resource "vault_pki_secret_backend_config_ca" "root" {
  backend             = vault_mount.pki_root.path
  pem_bundle          = tls_self_signed_cert.root.cert_pem
  depends_on          = [vault_mount.pki_root]
}

// Generate root CA certificate (self-signed)
// In production, import an external root CA
resource "tls_private_key" "root" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "root" {
  private_key_pem = tls_private_key.root.private_key_pem

  subject {
    common_name  = var.root_ca_common_name
    organization = "Phase P4"
  }

  validity_period_hours = 87600  # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "crl_signing"
  ]
}

// Configure intermediate CA mount
resource "vault_mount_tune" "pki_int_tune" {
  path = vault_mount.pki_intermediate.path

  max_lease_ttl_seconds = 157680000
  default_lease_ttl_seconds = 157680000
}

// Generate intermediate CSR
resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend      = vault_mount.pki_intermediate.path
  type         = "internal"
  common_name  = var.intermediate_ca_common_name
  organization = "Phase P4"
  depends_on   = [vault_mount.pki_intermediate]
}

// Sign intermediate CSR with root CA (in Vault)
resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate_signed" {
  backend             = vault_mount.pki_root.path
  csr                 = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name         = var.intermediate_ca_common_name
  organization        = "Phase P4"
  ttl                 = "43800h"  # 5 years
  max_ttl             = var.max_ttl
  use_csr_values      = true
  depends_on          = [vault_pki_secret_backend_config_ca.root]
}

// Set the signed intermediate cert in vault
resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_intermediate.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate_signed.certificate
  depends_on  = [vault_pki_secret_backend_root_sign_intermediate.intermediate_signed]
}

// Configure intermediate CA roles for issue
resource "vault_pki_secret_backend_role" "control_plane_role" {
  backend          = vault_mount.pki_intermediate.path
  name             = "control-plane-role"
  ttl              = "72h"
  max_ttl          = "720h"
  allowed_domains  = ["control-plane.example.local"]
  allow_subdomains = true

  allowed_other_sans = ["*.control-plane.svc.cluster.local", "control-plane"]

  key_type    = "rsa"
  key_bits    = 2048
  key_usage   = ["DigitalSignature", "KeyEncipherment"]
  ext_key_usage = ["ServerAuth", "ClientAuth"]

  require_cn             = true
  use_csr_common_name    = false
  enforce_hostnames      = true
  allow_any_name         = false
  server_flag            = true
  client_flag            = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.intermediate]
}

// Enable auto-tidy for old certificates
resource "vault_pki_secret_backend_config_auto_tidy" "auto_tidy" {
  backend                  = vault_mount.pki_intermediate.path
  enabled                  = true
  interval_duration        = 3600  # 1 hour
  tidy_expired_issuers     = true
  tidy_revoked_certs       = true
  tidy_revoked_cert_issuer_refs = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.intermediate]
}

output "root_ca_pem" {
  value       = tls_self_signed_cert.root.cert_pem
  description = "Root CA certificate PEM"
}

output "intermediate_ca_mount" {
  value       = vault_mount.pki_intermediate.path
  description = "Path to intermediate CA in Vault"
}

output "control_plane_role_name" {
  value       = vault_pki_secret_backend_role.control_plane_role.name
  description = "Name of the control-plane role for certificate issuance"
}

output "certificate_ttl" {
  value       = vault_pki_secret_backend_role.control_plane_role.ttl
  description = "TTL for issued certificates (auto-renewal recommended before expiry)"
}
