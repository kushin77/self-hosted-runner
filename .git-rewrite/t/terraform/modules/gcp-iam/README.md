# GCP Service Account Provisioning

This module provisions the GCP Service Account required for Vault auto-unseal and GCS storage.

## Resources Created:
- Service Account: `vault-ops-sa`
- IAM Role Bindings:
    - `roles/cloudkms.cryptoKeyEncrypterDecrypter`
    - `roles/storage.objectAdmin`
    - `roles/iam.serviceAccountTokenCreator`

## Application:
Include this in a root Terraform configuration to manage administrative credentials via code rather than manual commands.
