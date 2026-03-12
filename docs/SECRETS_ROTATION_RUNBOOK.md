SECRETS ROTATION RUNBOOK

Purpose
- Step-by-step runbook to rotate credentials removed from repo and to update secrets in Google Secret Manager (GSM), Vault, and AWS.

Prerequisites
- GitHub repo admin rights and ability to create PATs.
- GCP `gcloud` CLI authenticated against `nexusshield-prod` with permissions to access/modify Secrets Manager.
- Vault admin token or approle with permissions to create secret_ids (if Vault rotation required).
- AWS console access for IAM key rotation (or programmatic permissions).
- Local workstation: `gcloud`, `vault`, `aws`, `jq` installed.

High-level steps
1. Generate new GitHub PAT (manual)
   - Scopes: `repo`, `workflow`, `admin:repo_hook` (adjust per org policy)
   - Save PAT temporarily on workstation, then add to GSM:

     gcloud secrets versions add github-token --data-file=<(echo -n "<NEW_PAT>")

2. Rotate Vault AppRole secret_id (semi-automated)
   - If `vault-admin-token` exists in GSM, fetch it and generate a new secret_id:

     VAULT_ADDR=https://vault.example.com
     ADMIN_TOKEN=$(gcloud secrets versions access latest --secret=vault-admin-token)
     NEW_SECRET_ID=$(curl -s -X POST -H "X-Vault-Token: $ADMIN_TOKEN" "$VAULT_ADDR/v1/auth/approle/role/nexusshield-deployer/secret-id" -d '{}' | jq -r '.data.secret_id')
     echo -n "$NEW_SECRET_ID" | gcloud secrets versions add vault-secret-id --data-file=-

   - If `vault-admin-token` isn't present, use Vault UI/CLI with an admin account and manually update GSM.

3. Rotate AWS IAM keys (manual recommended)
   - Create a new access key for the CI user (e.g., `nexusshield-ci`) via AWS console or CLI.
   - Add new values to GSM:

     gcloud secrets versions add aws-access-key-id --data-file=<(echo -n "<NEW_AWS_KEY_ID>")
     gcloud secrets versions add aws-secret-access-key --data-file=<(echo -n "<NEW_AWS_SECRET_KEY>")

   - Validate workloads and rotate out old keys once tested.

4. Verify services and CI
   - Trigger Cloud Build validation pipeline (`validate-policies-and-keda`) and ensure status checks pass.
   - Verify no services break and rotate any runner/service credentials as needed.

5. Post-rotation tasks
   - Revoke old tokens/keys and record revocation in audit log.
   - Run `gitleaks` on sanitized repo mirrors to confirm no secrets remain.
   - If history rewrite performed, coordinate a maintenance window and follow `scripts/remediation/orchestrate_remediation.sh --apply` steps.

Notes
- The repository contains automation scripts for orchestration at `scripts/remediation/orchestrate_remediation.sh` and for history purge at `scripts/ops/run-purge-and-scan.sh`.
- Most rotation steps require manual credential generation or admin console access; the runbook provides commands to store new values in GSM once generated.

Contact
- If you want me to perform any of the above automated steps (validate tokens, push GSM updates, or run dry-run history purge), provide explicit confirmation and the necessary credentials or allow me to run with the existing `gcloud` auth shown in this environment.
