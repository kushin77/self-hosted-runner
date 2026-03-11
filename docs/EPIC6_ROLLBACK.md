# EPIC-6 Rollback Procedures

Use this document when a bootstrap or rotation introduces failures and you need to revert to last-known-good credentials or resource state.

Quick safety checklist
- Notify stakeholders and open incident ticket.
- Stop automated rollouts (`ps` / system that runs scripts) and pause monitors if needed.

Rollback Steps

1. Identify the last-known-good secret versions in GSM
   - List versions: `gcloud secrets versions list aws-secret-access-key --project=nexusshield-prod`
   - Choose the version ID that preceded the failing change.

2. Restore secret versions (GSM)
   - To make a previous version the current one, copy the value into a new version:
     - `gcloud secrets versions access <VERSION> --secret=<SECRET> --project=nexusshield-prod > /tmp/secret.value`
     - `gcloud secrets versions add <SECRET> --data-file=/tmp/secret.value --project=nexusshield-prod`

3. Update Vault mirrors (if used)
   - `vault kv put secret/aws/epic6 access_key_id="<id>" secret_access_key="<key>"`

4. For Azure Key Vault mirrors
   - Use `az keyvault secret set --vault-name <vault> --name <name> --value <value>` to replace with restored secret.

5. Re-run smoke tests
   - `scripts/epic6/run-smoke-tests.sh` and verify all checks pass.

6. If resource creation needs to be undone (users/keys)
   - AWS: remove newly created access keys: `aws iam delete-access-key --user-name <user> --access-key-id <key>`
   - GCP: delete newly created service account keys: `gcloud iam service-accounts keys delete <key-id> --iam-account=<sa-email>`
   - Azure: remove newly created credentials via `az ad sp credential delete --id <appId> --key-id <keyId>`

Post-rollback
- Document root cause, corrective action, and schedule secure rotation if needed.
- Re-enable monitors and resume automated workflows.
