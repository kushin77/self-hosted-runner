# How to Add a Credential Provider (Quick Guide)

This repo supports three credential providers for ephemeral credentials used by workflows:

- Google Secret Manager (GSM) — use Workload Identity Federation (OIDC) and a service account
- HashiCorp Vault — AppRole or token-based auth
- AWS — OIDC assume-role-with-web-identity to obtain temporary credentials

IMPORTANT: Do not store long-lived keys in the repository. Use GitHub Actions secrets for any required identifiers and let OIDC/WIF handle tokens.

Required secrets / env variables (one provider is enough to go live):

- For GSM (recommended):
  - `GCP_WORKLOAD_IDENTITY_PROVIDER` (OIDC provider ID)
  - `GCP_SERVICE_ACCOUNT` (service account email)
  - Optional: `GCP_PROJECT_ID`

- For Vault (fallback):
  - `VAULT_ADDR` (https://...)
  - `VAULT_ROLE_ID` and `VAULT_SECRET_ID` (AppRole) OR `VAULT_TOKEN` (short-lived)

- For AWS (tertiary):
  - `AWS_ROLE_TO_ASSUME` (ARN for role that allows OIDC)
  - `AWS_REGION`

How to add a provider quickly (example — GSM):
1. In GitHub repository → Settings → Secrets → Actions → New repository secret
2. Add `GCP_WORKLOAD_IDENTITY_PROVIDER` with your Workload Identity Provider value
3. Add `GCP_SERVICE_ACCOUNT` with your service account email
4. Optionally add `GCP_PROJECT_ID`

Verification (after adding):
- Use the `Validate Credentials` workflow (manual dispatch) to run the lightweight checks:
  - `.github/workflows/validate-credentials.yml` (Manual dispatch)
  - Or run `scripts/cred-setup/validate-credentials.sh` locally in a runner with the env vars present

Security notes:
- Never paste actual private keys into logs or issues.
- Use OIDC/WIF where possible to avoid storing secrets.

If you want, I can create the necessary GitHub Actions secret entries for you if you provide the secret values or give access to a secrets admin.
