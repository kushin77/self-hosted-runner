# Credential Hardening: Implementation Complete

Status: Implementation applied to `main` and local validations completed (2026-03-10).

Summary of changes
- `scripts/vault/sync_gsm_to_vault.sh`: prefer `VAULT_TOKEN_FILE`, AppRole fallback, transient token usage.
- `backend/src/credentials.ts`: Vault client now prefers token file then `VAULT_TOKEN` env; added robustness.
- `docker-compose.yml` and `.env.production.example`: removed persistent SA key mounts and added Workload Identity Federation (WIF) guidance.
- `docs/runbooks/credential_unblock_runbook.md`: operator runbook with one-liners.
- `docs/verification/credential_verification.md`: verification checklist.
- Local test harness: mocked `gcloud` and Vault dev validation scripts under `backend/scripts/`.

What was validated locally
- VAULT token selection: token-file preferred, then `VAULT_TOKEN` env.
- Mocked GSM → Vault sync using `scripts/vault/sync_gsm_to_vault.sh` with a mocked `gcloud` — confirmed secret written to local Vault KV v2.
- `getCredentialService().resolveCredential()` read secret from local Vault using token-file.

Operator actions required for cloud end-to-end validation
1. Enable Secret Manager API in target GCP project:

```bash
gcloud services enable secretmanager.googleapis.com --project=PROJECT_ID
```

2. Create Workload Identity Provider (WIF) and bind SA. Set runtime envs:

 - `GCP_WORKLOAD_IDENTITY_PROVIDER`
 - `GCP_SERVICE_ACCOUNT_EMAIL`

3. Provision Vault AppRole or deploy Vault Agent on runners to provide `/var/run/secrets/vault/token`.

4. (Optional) Provide AWS OIDC role and KMS key details: `AWS_ROLE_TO_ASSUME`, `AWS_KMS_KEY_ID`.

Where to look
- Runbook: `docs/runbooks/credential_unblock_runbook.md`
- Verification checklist: `docs/verification/credential_verification.md`
- Vault sync script: `scripts/vault/sync_gsm_to_vault.sh`

Next steps I will take on operator confirmation
- Perform cloud GSM→Vault→KMS validation and report results.
- Run Terraform apply if operator performs the one-time reauth or provides temporary credentials.
- Close remaining issues and create final deployment certificate.

If you want me to proceed immediately with cloud validation, provide WIF/AppRole credentials (or authorize operator contact) and I will validate end-to-end and finalize closure.
