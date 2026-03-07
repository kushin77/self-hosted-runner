# Phase 5 Operations Handoff — Complete

**Date**: March 7, 2026  
**Status**: ✅ Code-Complete | 🔄 Awaiting secret provisioning  
**Owner**: Ops team

---

## Overview

Phase 5 automation is **production-ready** and fully deployed to `main`. All workflows are idempotent, immutable, and designed for hands-off operation. The system is now waiting for **ops to provision 3 required secrets** to activate the automation.

## What's Included (Code-Complete ✅)

### 1. **GSM↔GitHub Secret Sync Workflow**
- **File**: `.github/workflows/sync-gsm-to-github-secrets.yml`
- **Trigger**: Every 6 hours (cron) + `workflow_dispatch` + `repository_dispatch` (manual-secret-sync)
- **Purpose**: Automatically sync secrets from GCP Secret Manager to GitHub repository secrets
- **Required secrets**: `GCP_SERVICE_ACCOUNT_KEY`, `GCP_PROJECT_ID`
- **Idempotent**: ✅ Can be run multiple times safely; only updates if values change
- **Audit**: Creates issues if sync fails due to missing credentials or permissions
- **Status**: ⚙️ Deployed, ready to activate

### 2. **Credential Rotation Workflows**

#### Monthly Rotation (GitHub tokens, SSH keys)
- **File**: `.github/workflows/credential-rotation-monthly.yml`
- **Trigger**: 1st of each month at 02:00 UTC + `workflow_dispatch`
- **Purpose**: Rotate GitHub PAT and SSH keys on a monthly schedule
- **Audit**: Creates immutable GitHub issues to log all rotations
- **Idempotent**: ✅ Safe to re-run

#### Quarterly Vault AppRole Rotation
- **File**: `.github/workflows/vault-approle-rotation-quarterly.yml`
- **Trigger**: Every 90 days (Q1, Q2, Q3, Q4) at 02:00 UTC + `workflow_dispatch`
- **Purpose**: Rotate Vault AppRole credentials to minimize exposure window
- **Audit**: Creates issues with rotation metadata
- **Idempotent**: ✅ Safe to re-run

### 3. **Runner Self-Heal Workflow**
- **File**: `.github/workflows/runner-self-heal.yml`
- **Trigger**: Every 5 minutes (cron) + `workflow_dispatch`
- **Purpose**: Monitor runner status; auto-restart offline runners via SSH/Ansible
- **Required secrets**: `RUNNER_MGMT_TOKEN`, `DEPLOY_SSH_KEY` (optional but recommended)
- **Graceful degradation**: ✅ Works without secrets; creates issues if runners offline and no SSH key
- **Idempotent**: ✅ Safe to run frequently
- **Audit**: Creates GitHub issues when manual intervention needed
- **Status**: ⚙️ Deployed, ready to activate

### 4. **Slack Notifications Workflow**
- **File**: `.github/workflows/slack-notifications.yml`
- **Trigger**: Acts as a reusable workflow; called by other workflows on key events
- **Purpose**: Send critical alerts (rotation events, failures, offline runners) to Slack
- **Required secrets**: `SLACK_WEBHOOK_URL` (optional; skipped if not provided)
- **Idempotent**: ✅ Safe to re-run
- **Status**: ⚙️ Deployed, ready to activate

### 5. **Supporting Documentation**
- **PHASE_5_OPS_RUNBOOK.md**: Day-2 runbook for common tasks
- **docs/GSM_VAULT_INTEGRATION.md**: Architecture & integration details
- **docs/SECRETS_RUNBOOKS_AUDIT.md**: How to audit and verify secrets
- **docs/EMERGENCY_CREDENTIAL_RECOVERY.md**: Emergency procedures

### 6. **Automation Scripts**
- **scripts/automation/**: Helper scripts for idempotency validation, deployment verification
- **scripts/runner/**: Runner management (ephemeral cleanup, auto-heal)
- **scripts/setup-automation-secrets*.sh**: Bulk secret provisioning helpers

---

## Secrets Provisioning Checklist

### ⚠️ BLOCKING: 3 Required Secrets

See **[Issue #1038](https://github.com/kushin77/self-hosted-runner/issues/1038)** for step-by-step provisioning.

#### 1. **GCP Service Account Key** (Issue #1035)
```bash
gh secret set GCP_SERVICE_ACCOUNT_KEY --repo kushin77/self-hosted-runner --body "$(cat /path/to/gcp-key.json)"
gh secret set GCP_PROJECT_ID --repo kushin77/self-hosted-runner --body "your-gcp-project-id"
```

#### 2. **Runner Management Token** (Issue #1036)
```bash
gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "github_pat_..."
```

#### 3. **Deploy SSH Key** (Issue #1037)
```bash
gh secret set DEPLOY_SSH_KEY --repo kushin77/self-hosted-runner --body "$(cat ~/.ssh/runner_deploy_key)"
```

### 🟢 OPTIONAL: Slack Webhook URL
```bash
gh secret set SLACK_WEBHOOK_URL --repo kushin77/self-hosted-runner --body "https://hooks.slack.com/services/..."
```

---

## Activation Steps (After Provisioning)

### 1. **Verify Secrets**
Run the ops verification script:
```bash
./scripts/automation/verify-secrets-provisioned.sh
```

### 2. **Trigger GSM Sync**
```bash
gh workflow run sync-gsm-to-github-secrets.yml -R kushin77/self-hosted-runner --ref main
```
Check logs: https://github.com/kushin77/self-hosted-runner/actions/workflows/sync-gsm-to-github-secrets.yml

### 3. **Trigger Runner Self-Heal**
```bash
gh workflow run runner-self-heal.yml -R kushin77/self-hosted-runner --ref main
```
Expect runners to be healthy; verify in Actions tab.

### 4. **Validate Automation**
```bash
# Check all scheduled workflows are active
gh api repos/kushin77/self-hosted-runner/actions/schedules --jq '.[] | {id:.id, name:.name}'

# List recent workflow runs
gh run list -R kushin77/self-hosted-runner --limit 10
```

---

## Idempotency Guarantees

All workflows are **idempotent** and safe to run concurrently:

- ✅ **GSM Sync**: Only updates GitHub secrets if values change; no side effects if run multiple times
- ✅ **Rotations**: Create immutable audit issues; can be re-run without corruption
- ✅ **Self-Heal**: Checks runner status; only restarts if offline; safe at 5-minute intervals
- ✅ **Slack Notifications**: Re-runs produce duplicate messages only (acceptable trade-off for resilience)

---

## Scheduled Executions (After Provisioning)

| Workflow | Schedule | Interval | Purpose |
| --- | --- | --- | --- |
| GSM Sync | Cron: `0 */6 * * *` | Every 6 hours | Self-healing secrets sync |
| Runner Self-Heal | Cron: `*/5 * * * *` | Every 5 minutes | Runner health check & restart |
| Monthly Rotation | Cron: `0 2 1 * *` | 1st of month, 02:00 UTC | Token/SSH key rotation |
| Quarterly AppRole | Cron: `0 2 1 */3 *` | Every 90 days, 02:00 UTC | Vault AppRole rotation |

---

## Audit & Observability

### GitHub Issues (Immutable Audit Trail)
- Rotation events → Issue created with timestamp, actor, scope
- Sync failures → Issue created with error details, required actions
- Runner offline → Issue created with status, manual recovery options

### Workflow Logs
- All workflows log to GitHub Actions tab
- Logs retained per GitHub retention policy (90 days default)
- Sensitive data (credentials, keys) automatically masked

### Recommended Monitoring
1. **Subscribe to GitHub issue notifications** (labels: `automation`, `ops`, `security`)
2. **Pin workflows to a Slack channel** (if SLACK_WEBHOOK_URL configured)
3. **Weekly audit runs**:
   ```bash
   ./scripts/automation/audit-secrets-usage.sh
   ./scripts/automation/validate-idempotency.sh
   ```

---

## Troubleshooting

### Workflow Won't Trigger
- Check branch protection rules: workflows on `main` require branch protections
- Verify `GITHUB_TOKEN` has `actions: write` permission

### Secrets Not Syncing
- See **Issue #1038** for detailed remediation
- Verify `GCP_SERVICE_ACCOUNT_KEY` is **valid JSON** (not truncated)
- Confirm service account has **Secret Manager viewer** role in GCP

### Runners Offline After Self-Heal
- Verify `DEPLOY_SSH_KEY` is present and correct
- Check SSH connectivity to runner hosts: `ssh -i ~/.ssh/runner_deploy_key runner@host`
- Consult **docs/EMERGENCY_CREDENTIAL_RECOVERY.md**

---

## Next Steps for Ops

1. **Priority 1**: Provision 3 required secrets (Issue #1038)
2. **Priority 2**: Run verification script and trigger GSM sync
3. **Priority 3**: Monitor first few runner-self-heal cycles
4. **Priority 4**: (Optional) Configure Slack webhook for real-time alerts
5. **Priority 5**: Schedule weekly audit runs via cron or CI/CD

---

## Success Criteria

- ✅ All 3 secrets provisioned and verified
- ✅ GSM sync completes successfully; no missing secrets warnings
- ✅ Runner self-heal runs successfully; no offline runners
- ✅ Slack notifications (if configured) deliver rotation & failure alerts
- ✅ Weekly verification scripts run without errors

---

## Support & Escalation

- **Workflow failures**: Check GitHub Actions logs; create issue if unresolved
- **Secret provisioning help**: See issue #1038 (copy-paste commands provided)
- **Emergency credential recovery**: See docs/EMERGENCY_CREDENTIAL_RECOVERY.md
- **Architecture questions**: See docs/GSM_VAULT_INTEGRATION.md

---

**Phase 5 is production-ready. Ops teams: proceed to Issue #1038 to begin secret provisioning.**

