# EPIC-6 Runbook — Cross-Cloud Credential Orchestration

Purpose
- Provide an operator-focused runbook for EPIC-6 automation: provisioning, verification, and maintenance of cross-cloud credentials (AWS, GCP, Azure).

Scope
- Idempotent bootstrap of AWS IAM user, GCP service account, and Azure service principal.
- Multi-layer secret storage: GSM (canonical) → Vault (mirror) → Azure Key Vault (mirror for Azure workloads).
- Automated verification via smoke tests and continuous monitor.

Prerequisites
- `gcloud`, `az`, `aws`, `vault`, `jq`, and `curl` installed and authenticated where required.
- Access to GCP project `nexusshield-prod` and Vault operator token (if Vault used).

Runbook Steps

1. Bootstrap (automated)
   - AWS: `scripts/aws/setup-aws-iam-role.sh --iam-policy-file policy.json --project nexusshield-prod`
   - GCP: `scripts/gcp/setup-gcp-service-account.sh --project nexusshield-prod --sa-name epic6-operator-sa --roles "roles/storage.objectAdmin,roles/iam.serviceAccountUser"`
   - Azure: `scripts/setup-azure-tenant-api-direct.sh --subscription $SUBSCRIPTION_ID --auto` (already implemented)

2. Verify (automated)
   - Run cross-cloud smoke tests: `scripts/epic6/run-smoke-tests.sh`
   - Check EPIC-5 monitor: `tail -n 200 logs/epic-5-monitor/epic5-monitor.log`

3. Audit
   - Confirm secrets present in GSM:
     - `gcloud secrets versions access latest --secret=azure-client-id --project=nexusshield-prod`
     - `gcloud secrets versions access latest --secret=aws-access-key-id --project=nexusshield-prod`
     - `gcloud secrets versions access latest --secret=gcp-epic6-operator-sa-key --project=nexusshield-prod`
   - Confirm mirrored secrets in Vault (if used): `vault kv get secret/aws/epic6`

4. Rotate credentials (idempotent)
   - Re-run bootstrap scripts to rotate keys; the scripts add new secret versions in GSM and update Vault mirrors.
   - Re-run smoke tests to validate rotation succeeded.

5. Emergency rollback
   - If an automated change causes failures, run rollback steps in `EPIC6_ROLLBACK.md`.

Contact
- Owners: @kushin77 (repo owner)
- On-call: infra-ops (pager channel)
