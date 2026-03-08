# Secret Management for Observability E2E Automation

This document provides a unified overview of three secret management approaches for syncing secrets into GitHub Actions for the Observability E2E runs.

## Overview

Required secrets for E2E automation:
- `SLACK_WEBHOOK_URL` — for posting test results
- `PAGERDUTY_SERVICE_KEY` — for PagerDuty incident trigger
- `PAGERDUTY_API_TOKEN` (optional, recommended) — for PagerDuty read operations

All three options below support:
- Immutable secrets (read from external systems, temporary files used during sync)
- Ephemeral handling (no secrets stored in code)
- Idempotent workflows (safe to re-run, same outcome)
- Hands-off automation (once configured, workflows can run automatically)

---

## Option 1: GCP Secret Manager (GSM)

**Use this if:** You have a GCP project and prefer Workload Identity Federation.

Script: `scripts/ops/gsm_sync.sh`  
Workflow: `.github/workflows/gsm-sync-run.yml` (requires `workflow_dispatch` or cron triggering)  
Docs: `docs/GSM_SYNC.md`

### Setup

1. Store secrets in GCP Secret Manager (e.g., `projects/YOUR_PROJECT/secrets/slack-webhook`).
2. Configure Workload Identity Federation between GitHub (repo) and GCP service account.
3. Add repo secrets:
   - `GCP_WORKLOAD_IDENTITY_PROVIDER` 
   - `GCP_SERVICE_ACCOUNT_EMAIL`
   - `GCP_PROJECT_ID`
4. Run the workflow (UI or CLI):
   ```bash
   gh workflow run gsm-sync-run.yml --repo kushin77/self-hosted-runner --ref main
   ```

### Notes
- OIDC-based authentication; no long-lived credentials needed.
- Best for teams already using GCP.

---

## Option 2: HashiCorp Vault

**Use this if:** You have Vault deployed (Datacenter or Cloud) and prefer token/AppRole auth.

Script: `scripts/ops/vault_sync.sh`  
Workflow: `.github/workflows/vault-sync-run.yml` (manual `workflow_dispatch`)  
Docs: `docs/VAULT_SYNC.md`

### Setup

1. Store secrets in Vault KV v2 (e.g., `secret/data/prod/slack` with key `webhook_url`).
2. Configure Vault authentication (token, AppRole, or OIDC).
3. Add repo secrets:
   - `VAULT_ADDR` (e.g., `https://vault.example:8200`)
   - `VAULT_TOKEN` (for quick start) or AppRole creds (more secure)
4. Run the workflow:
   ```bash
   gh workflow run vault-sync-run.yml --repo kushin77/self-hosted-runner --ref main
   ```

### Notes
- Flexible auth options (token, AppRole, OIDC).
- Scales well for multi-team secret management.
- Good for teams already using Vault.

---

## Option 3: AWS KMS with Encrypted Secrets

**Use this if:** You have AWS and want to encrypt secrets at rest using KMS.

Script: `scripts/ops/kms_decrypt.sh`  
Workflow: `.github/workflows/kms-decrypt-run.yml` (requires OIDC or IAM creds)  
Docs: `docs/KMS_DECRYPT.md`

### Setup

1. Create KMS key in AWS (or use existing).
2. Encrypt secrets using KMS (or store in Systems Manager Parameter Store encrypted with your key).
3. Configure OIDC for GitHub → AWS or add long-lived IAM credentials.
4. Add repo secrets:
   - `AWS_REGION`
   - `AWS_ROLE_ARN` (for OIDC) or `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
   - `KMS_KEY_ID` (optional, if not inferred from encrypted data)
5. Run the workflow:
   ```bash
   gh workflow run kms-decrypt-run.yml --repo kushin77/self-hosted-runner --ref main
   ```

### Notes
- KMS encryption at rest; audit trail in CloudTrail.
- OIDC recommended to avoid long-lived credentials.
- Good for teams already using AWS.

---

## Comparison Matrix

| Feature | GSM | Vault | KMS |
|---------|-----|-------|-----|
| **Authentication** | OIDC (WIF) | Token/AppRole/OIDC | OIDC/IAM |
| **Audit Trail** | Cloud Logging | Audit device logs | CloudTrail |
| **Multi-region** | No (per GCP project) | Yes (HA deployments) | Yes (cross-region replication) |
| **Setup Complexity** | Moderate (WIF config) | Moderate (Vault deployment) | Moderate (AWS account setup) |
| **Cost per request** | ~$0.06/100k | Varies (self-hosted or cloud) | Within AWS free tier typically |

---

## Recommended Workflow

1. **Choose one** of the three options above (GSM, Vault, or KMS) based on your existing infrastructure.
2. **Run the corresponding sync workflow** to populate GitHub repo secrets.
3. **Monitor success:** After sync, re-run the secret-check workflow:
   ```bash
   gh workflow run observability-e2e-secret-check.yml --repo kushin77/self-hosted-runner --ref main
   ```
4. **Automated E2E runs:** Once secrets are present, the scheduled E2E runs will exercise real receivers (Slack, PagerDuty). The postprocess workflow automatically collects metrics and posts results to issue #1370.

---

## Ops Issues & Links

- **GSM Onboarding:** Issue #1431
- **Vault Onboarding:** Issue #1432
- **KMS Onboarding:** Issue #1433
- **Secret Check (validation):** Issue #1378
- **Delivery Tracking:** Issue #1370

---

## Troubleshooting

- **Script execution fails:** Ensure the script is executable (`chmod +x scripts/ops/*.sh`) and required tools are installed (`gcloud`, `vault`, or AWS CLI).
- **Secret not found:** Check that the path/key exists in the external system (GSM, Vault, KMS).
- **gh secret set fails:** Verify the `gh` token has `repo` scope and the principal has write permissions to repo secrets.
- **Workflow runs but posts no comment:** Ensure issue numbers are correct and permissions are set (Issues: write in workflow).

---

## Security Best Practices

- **No secrets in code:** All scripts use temporary files and cleanup after sync.
- **Minimize credential lifetime:** Use OIDC where possible; rotate credentials regularly.
- **Audit access:** Enable audit logging on all secret management systems (Vault audit, CloudTrail, Cloud Logging).
- **Least privilege:** Grant read-only access to the secrets needed; restrict write access to GitHub Secrets to the sync workflow.
