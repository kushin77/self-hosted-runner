# Operator Runbook — GSM / Vault / KMS Unblock

Purpose: steps to enable and verify cloud and Vault prerequisites so automation can run using ephemeral credentials (GSM → Vault → KMS).

1) Enable Secret Manager API (GCP)

- Run as an org/project admin:

```bash
gcloud services enable secretmanager.googleapis.com --project=PROJECT_ID
```

2) Create Workload Identity Federation (WIF) provider and bind SA

- Create provider (adjust pool/provider names):

```bash
gcloud iam workload-identity-pools create WIF_POOL --location="global" --project=PROJECT_ID
gcloud iam workload-identity-pools providers create-oidc WIF_PROVIDER \
  --workload-identity-pool=WIF_POOL --issuer-uri="https://sts.googleapis.com" --project=PROJECT_ID
```

- Grant service account impersonation to the pool subject and record provider identifier for runtime env `GCP_WORKLOAD_IDENTITY_PROVIDER`.

3) Vault AppRole creation (Vault admin)

- Create AppRole for automation runner and capture `role_id` and `secret_id`:

```bash
vault auth enable approle
vault write auth/approle/role/automation-runner token_ttl=1h token_max_ttl=24h policies="automation"
vault read -field=role_id auth/approle/role/automation-runner/role-id
vault write -f auth/approle/role/automation-runner/secret-id
```

- Store `role_id` and `secret_id` into secure operator-only secrets store (not checked into git). Optionally configure Vault Agent on the runner to write a token to `/var/run/secrets/vault/token`.

4) Vault Agent (recommended) — on-runner token sink

- Example minimal config (runs as systemd):

```hcl
pid_file = "/var/run/vault-agent.pid"
listener "tcp" {}
auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/run/secrets/vault/role_id"
      secret_id_file_path = "/run/secrets/vault/secret_id"
    }
  }
  sink "file" {
    config = { path = "/var/run/secrets/vault/token" }
  }
}
```

5) AWS OIDC & KMS (if using AWS tertiary)

- Create an IAM role for OIDC and allow the runner to assume. Record `AWS_ROLE_TO_ASSUME` and `AWS_KMS_KEY_ID`.

6) Terraform / GCP reauth for operator flows

- If Terraform requires a one-time RAPT browser flow, run terraform apply locally with `GOOGLE_APPLICATION_CREDENTIALS` set on an operator machine or use WIF impersonation.

7) Verification checklist

- Secret Manager API responds: `gcloud secrets list --project=PROJECT_ID`
- Vault Agent writes `/var/run/secrets/vault/token`
- `./scripts/vault/sync_gsm_to_vault.sh` can fetch secret and write to Vault using token-file or AppRole
- Backend can read `VAULT_TOKEN_FILE` and access secrets

Links:
- [scripts/vault/sync_gsm_to_vault.sh](scripts/vault/sync_gsm_to_vault.sh)
- [docs/runbooks/credential_unblock_runbook.md](docs/runbooks/credential_unblock_runbook.md)
