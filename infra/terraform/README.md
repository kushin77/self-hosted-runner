# Infrastructure templates for secrets orchestration

This folder contains minimal, idempotent Terraform templates to provision
the GCP resources commonly required by the operator bootstrap:

- KMS key ring and crypto key
- Workload Identity Pool and Provider (WIF)

These templates are intentionally minimal and require operator credentials
to run. Follow the operator bootstrap in the repo root to provision:

1. Configure Google authentication, for example:

```bash
# Export a service account JSON or use gcloud auth application-default login
export GOOGLE_CREDENTIALS="$(cat ~/sa-key.json)"
export TF_VAR_project_id="my-project-id"
```

2. From repo root run:

```bash
chmod +x infra/setup-secrets-orchestration.sh
./infra/setup-secrets-orchestration.sh --apply
```

Notes:
- The `setup-secrets-orchestration.sh` script performs `terraform init` and
  `terraform apply` in `infra/` when run with `--apply`.
- The templates emit outputs you can use to set repository secrets (GCP_WORKLOAD_ID_PROVIDER,
  AWS_KMS_KEY_ID equivalent, etc.).
- Vault provisioning is environment-specific; use the Vault API or Terraform `vault` provider
  after setting `VAULT_ADDR` and authentication.
