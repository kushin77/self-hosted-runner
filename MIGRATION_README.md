# Secrets Migration — Summary & How to Run

Status: dry-run completed (see `.migration-audit/` and `migration-report-*.json`).

Steps to run live migration (Tier‑1 example):

1. Ensure provider credentials are available to the runner (use OIDC where possible).
2. Inspect `migration-report-*.json` and pick secrets for live migration.
3. Run provider push scripts (example):

```bash
# GSM
bash scripts/migrate/push-to-gsm.sh --name "GOOGLE_CREDENTIALS" --value "$(cat key.json)" \
  --project my-project

# Vault
bash scripts/migrate/push-to-vault.sh --name "COSIGN_KEY" --value "$(cat cosign.key)" \
  --mount secret

# AWS SecretsManager
bash scripts/migrate/push-to-kms.sh --name "AWS_KMS_KEY_ID" --value "abc123"
```

4. Verify `.migration-audit/` contains append-only JSONL entries for each push.
5. Update workflows to remove hard-coded secrets and source them at runtime via the `get-ephemeral-credential` action.

Notes:
- All push scripts support `--dry-run` and will not write to providers.
- Live runs require proper provider permissions and should be executed from a secure runner environment.
