# Credential Verification Checklist

Purpose: concise validation steps to confirm the repo changes for ephemeral credentials (GSM → Vault → KMS) have been applied and work end-to-end.

Prerequisites
- Vault reachable and unsealed
- Secret Manager API enabled for target GCP project
- AppRole created or Vault Agent configured on runner
- Workload Identity Provider created and bound to SA (if using WIF)

Verification Steps

1) Check Secret Manager API

```bash
gcloud secrets list --project=PROJECT_ID
```

2) Verify Vault AppRole (or Vault Agent)

- AppRole exists and returns role_id/secret_id:

```bash
vault read -field=role_id auth/approle/role/automation-runner/role-id
vault write -f auth/approle/role/automation-runner/secret-id
```

- If using Vault Agent, confirm token sink is present:

```bash
sudo cat /var/run/secrets/vault/token
```

3) Run vault sync script (operator-run)

```bash
# Example using AppRole envs
VAULT_ADDR=https://vault.example:8200 VAULT_ROLE_ID=... VAULT_SECRET_ID=... SECRET_NAME=my-secret VAULT_PATH=secret/data/my-secret ./scripts/vault/sync_gsm_to_vault.sh
```

Expect: "OK: secret synced to Vault"

4) Confirm backend reads Vault via token file

```bash
# On runner where /var/run/secrets/vault/token exists
node -e "const svc=require('./backend/dist/credentials').getCredentialService(); svc.resolveCredential('my-secret').then(console.log).catch(console.error)"
```

Expect: credential value returned and JSONL audit entry appended in `backend/logs/credential-audit.jsonl`.

5) Verify immutable audit trail

- Check `backend/logs/credential-audit.jsonl` contains access/rotate events.

6) Verify idempotence

- Re-run the sync and resolution commands; confirm no duplicate side-effects and audit entries are append-only.

7) Optional AWS KMS check

- If using AWS tertiary layer, verify role assumption and KMS decrypt path.

Notes
- Avoid checking in any role_id/secret_id/keys into Git. Store those in an operator-only secret store.
- If anything fails, attach `backend/logs/credential-audit.jsonl` and systemd/journal logs to the related GitHub issue.
