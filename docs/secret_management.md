Secret Management: Vault ↔ GSM + KMS (recommended)

Overview

- Store primary secrets in HashiCorp Vault (or another secret backend) for operator workflows.
- Use a short-lived sync process to copy necessary runtime secrets into Google Secret Manager (GSM) for Cloud Build and GCP workloads.
- Encrypt secrets with Cloud KMS; use a KMS key created in `terraform/phase0-core`.

Sync pattern

1. Vault holds canonical secret values.
2. A controller (CI job or Cloud Scheduler-triggered Cloud Run job) reads from Vault, validates ACLs, and writes to GSM.
3. GSM provides access to Cloud Build and runtime service accounts via IAM bindings (roles/secretmanager.secretAccessor).
4. Rotate keys/versions by creating new secret versions in GSM and rotating KMS keys per policy.

Notes

- Never commit secret payloads to the repo.
- Ensure the sync process runs with least privilege.
- Use Cloud KMS to encrypt any local artifacts and manage rotation with Terraform (or manually if required).