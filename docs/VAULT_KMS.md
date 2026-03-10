# Vault KMS Auto-Unseal (Terraform)

This file documents the Terraform-managed KMS resources for Vault auto-unseal that were added to the repo.

Files added:
- `terraform/vault_kms.tf` — creates a `google_kms_key_ring` and `google_kms_crypto_key` and grants `roles/cloudkms.cryptoKeyEncrypterDecrypter` to a specified service account.

How it works:
- Vault (or the Vault KMS plugin) uses the KMS key to encrypt/unseal the master key. The Terraform resources create the keyring and crypto key; you must provide the Vault service account email so the key IAM binding is applied.

Usage (operator):

1. Configure Terraform variables when running apply (example):

```bash
TF_VAR_gcp_project=nexusshield-prod \
TF_VAR_environment=production \
TF_VAR_vault_service_account_email=vault-sa@my-project.iam.gserviceaccount.com \
terraform -chdir=terraform apply -auto-approve
```

2. Ensure the service account exists and is used by the Vault process (e.g., Kubernetes workload identity, VM service account, or a dedicated service account for the host automation runner).

3. On the Vault side, configure the KMS auto-unseal stanza to reference the created key. Example (Vault configuration snippet):

```hcl
seal "gcpckms" {
  project     = "nexusshield-prod"
  region      = "us"
  key_ring    = "production-portal-vault-keyring"
  crypto_key  = "production-portal-vault-unseal-key"
}
```

Notes and best practices:
- Use workload identity (GKE) or VM service accounts rather than long-lived keys where possible.
- Rotate keys per your KMS policy; Vault auto-unseal remains compatible when keys are rotated.
- The Terraform IAM binding is conditional: it only applies if `vault_service_account_email` is set (non-empty).

Security:
- Restrict access to the KMS key to only the Vault service account and security admin principals.
- Audit key usage with Cloud Audit Logs.
