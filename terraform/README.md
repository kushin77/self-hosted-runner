GCP Vault Infra (KMS + GCS)

Purpose
- Provision a KMS key + key ring for Vault auto-unseal and a versioned, encrypted GCS bucket for Vault storage.

Quick start (recommended):
1. Create a GCP Service Account with `roles/storage.admin` and `roles/cloudkms.admin` (or the minimal roles described in the runbook).
2. Download the service account key JSON and keep it local (do NOT commit it).

Apply (example):

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
cd terraform
terraform init
terraform apply -var="project_id=your-gcp-project-id" -auto-approve
```

Best practices
- Use Workload Identity Federation / OIDC for CI instead of long-lived SA keys.
- Store state in a remote backend (GCS) and enable locking where possible.
- Review `prevent_destroy` on KMS keys before applying in production.

Next steps after apply
- Configure Vault to use the returned `vault_kms_key_id` for `auto_unseal`.
- Configure Vault to use the GCS bucket as the storage backend.
