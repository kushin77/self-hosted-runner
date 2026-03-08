# Vault Bootstrap Module

This folder contains automation patterns for deploying HashiCorp Vault (Helm/K8s or standalone).

Usage:
- The `deploy-cloud-credentials.yml` workflow will run Terraform or other provisioning steps here.
- The module should perform an idempotent deployment and return outputs: `vault_addr`, `vault_namespace`.

Important: Vault unseal automation will require access to a KMS or auto-unseal configuration.
