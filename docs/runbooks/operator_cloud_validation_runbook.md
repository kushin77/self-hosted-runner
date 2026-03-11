# Operator Cloud Validation Runbook

Purpose: Provide one-liners and checklist for operator to enable cloud APIs and provide WIF/AppRole so automated validation can run.

Checklist:

- Enable Secret Manager API for the target project:

  gcloud services enable secretmanager.googleapis.com --project=YOUR_PROJECT_ID

- Create Workload Identity Pool and Provider (if using WIF):

  # create pool
  gcloud iam workload-identity-pools create my-pool --project=YOUR_PROJECT_ID --location="global" --display-name="runner-pool"

  # create provider
  gcloud iam workload-identity-pools providers create-oidc my-provider \
    --project=YOUR_PROJECT_ID --location="global" --workload-identity-pool="my-pool" \
    --display-name="runner-provider" \
    --issuer-uri="https://accounts.google.com" \
    --attribute-mapping="google.subject=assertion.sub"

- Bind the provider to a Service Account and set `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT_EMAIL` in runner envs.

- Provision Vault AppRole (or ensure Vault Agent token sink is deployed):

  # operator example: create approle
  vault write auth/approle/role/runner-role token_ttl=1h token_max_ttl=4h secret_id_ttl=10m
  vault read auth/approle/role/runner-role/role-id
  vault write -f auth/approle/role/runner-role/secret-id

  # add `VAULT_ROLE_ID` and `VAULT_SECRET_ID` to secure operator store and provide to validation script

- Optional: Ensure AWS KMS key exists and `AWS_KMS_KEY_ID` is provided to validation if expected.

Run automated cloud validation (after above steps completed):

  export GCP_PROJECT=your-project-id
  export GCP_WORKLOAD_IDENTITY_PROVIDER="projects/PROJECT_BASE64_BLOB_REDACTED-pool/providers/my-provider"
  export GCP_SERVICE_ACCOUNT_EMAIL="svc-account@${GCP_PROJECT}.iam.gserviceaccount.com"
  export VAULT_TKN_FILE=/var/run/secrets/vault/token OR export VAULT_TKN=...
  ./scripts/cloud/validate_gsm_vault_kms.sh

If validation fails, share the script output and `journalctl`/runner logs with the security operator.
