Workload Identity Runbook (GitHub Actions -> GCP)

Goal
- Allow GitHub Actions to impersonate the Vault service account securely via Workload Identity (OIDC), avoiding long-lived service account keys.

Prereqs
- `gcloud` CLI authenticated with permissions to create workload-identity-pools and bind service accounts.
- `terraform apply` of `module.gcp_vault` to provision the Vault GCS bucket, KMS key, and Vault service account (use `scripts/terraform_apply.sh`).
- Optional: credentials stored in GSM and loaded via `scripts/load_gsm_secrets.sh` (see README).  

Quick steps (gcloud)
1. Create the pool:
   PROJECT_ID=your-project-id ./scripts/create_workload_identity.sh owner/repo

2. The script will create the pool and OIDC provider, discover the Vault SA (by display name), and bind the SA to allow members from the specified repo to impersonate it.

3. In GitHub Actions, use the `google-github-actions/auth` action to exchange the OIDC token for a short-lived credential:

```yaml
- name: 'Authenticate to GCP'
  uses: 'google-github-actions/auth@v1'
  with:
    workload_identity_provider: 'projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider'
    service_account: 'vault-admin-primary@PROJECT_ID.iam.gserviceaccount.com'
```

Notes & Best Practices
- Use `principalSet` bindings scoped to the specific repository (owner/repo) to limit trust.
- Avoid creating long-lived SA keys. If a key is required (for one-off automation), create it, use it, then delete it.
- Validate with a test workflow that requests an OIDC token and accesses KMS/GCS operations allowed to the service account.
- Record the Terraform outputs (`vault_kms_key_id`, `vault_storage_bucket`, `vault_service_account_email`) and use them to configure Vault's `auto_unseal` and storage section.

Terraform alternative
- If you prefer Terraform to create the Workload Identity resources, create a separate module and pin the `google` provider to a known working version. Due to provider schema differences across versions, I recommend using the `gcloud` script for initial setup and capturing returned IDs for reproducible infrastructure as code.
