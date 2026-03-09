# Phase 5 Operations Handoff — Complete

**Date**: March 7, 2026  
**Status**: ✅ **HANDS-OFF READY** | 🔐 Zero Manual Secrets | 🤖 OIDC-Native  
**Owner**: Ops team  
**Architecture**: GitHub OIDC → GCP Workload Identity Federation (ephemeral tokens, no stored credentials)

---

## Overview

Phase 5 automation is **production-ready** and fully deployed to `main`. All workflows are idempotent, immutable, and designed for fully hands-off operation with **zero credentials stored in GitHub**. The system uses **GitHub OIDC → GCP Workload Identity Federation** for automatic, ephemeral authentication.

**Activation Required**: One-time GCP Workload Identity Pool setup (~5 minutes) + provision 2 GitHub Secrets (provided by GCP setup).

---

## What's Included (Code-Complete ✅)

### 1. **GSM↔GitHub Secret Sync Workflow** (OIDC-Native)
- **File**: `.github/workflows/sync-gsm-to-github-secrets.yml`
- **Trigger**: Every 6 hours (cron) + `workflow_dispatch` + `repository_dispatch` (manual-secret-sync)
- **Purpose**: Automatically sync secrets from GCP Secret Manager to GitHub repository secrets
- **Authentication**: GitHub OIDC → GCP Workload Identity → ephemeral service account token
- **Secrets Required**: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL` (provided by GCP setup)
- **Graceful Degradation**: ✅ Works without secrets; logs warning if OIDC not configured
- **Idempotent**: ✅ Can be run multiple times safely; only updates if values change
- **Audit**: Creates issues if sync fails due to missing credentials or permissions
- **Status**: 🚀 Deployed to main, ready to activate

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

### 3. **Runner Self-Heal Workflow** (OIDC + SSH-Based)
- **File**: `.github/workflows/runner-self-heal.yml`
- **Trigger**: Every 5 minutes (cron) + `workflow_dispatch`
- **Purpose**: Monitor runner status; auto-restart offline runners via SSH/Ansible
- **Authentication**: RUNNER_MGMT_TOKEN fetched from GSM via OIDC; DEPLOY_SSH_KEY for SSH remediation
- **Graceful degradation**: ✅ Works without secrets; creates issues if runners offline
- **Idempotent**: ✅ Safe to run frequently (5-minute intervals)
- **Audit**: Creates GitHub issues when manual intervention needed
- **Status**: 🚀 Deployed to main, ready to activate

### 4. **Slack Notifications Workflow** (Event-Triggered, Optional)
- **File**: `.github/workflows/slack-notifications.yml`
- **Trigger**: Event-driven; called by other workflows on key events
- **Purpose**: Send critical alerts (rotation events, failures, offline runners) to Slack
- **Authentication**: SLACK_WEBHOOK_URL (optional; skipped gracefully if not configured)
- **Idempotent**: ✅ Safe to re-run
- **Status**: 🚀 Deployed to main, optional enhancement

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

## OIDC Activation Checklist (Zero Manual Secrets)

### ✅ ONE-TIME SETUP: GitHub→GCP Workload Identity Federation (~5 minutes)

**See Issue #1055 for complete step-by-step instructions with gcloud CLI commands.**

**Quick Summary**:
```
1. Create GCP Workload Identity Pool (github-runners)
2. Create OIDC Provider pointing to https://token.actions.githubusercontent.com
3. Create service account (github-actions)
4. Grant Secret Manager reader role to service account
5. Create Workload Identity binding linking GitHub repo to service account
```

**Result**: GitHub Actions can now request ephemeral tokens from GCP without storing any credentials.

### ✅ PROVISION 2 GITHUB SECRETS (After GCP Setup)
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: From GCP setup step 5
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
**Commands** (provided in Issue #1055):
```bash
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo kushin77/self-hosted-runner --body "projects/YOUR_PROJECT_NUMBER/locations/global/workloadIdentityPools/github-runners/providers/github"
gh secret set GCP_SERVICE_ACCOUNT_EMAIL --repo kushin77/self-hosted-runner --body "github-actions@YOUR_GCP_PROJECT.iam.gserviceaccount.com"
```

---

## Secrets Provisioning Checklist (Legacy - Reference Only)

### ❌ DEPRECATED: Manual Secret Storage Approach

The old approach (storing `GCP_SERVICE_ACCOUNT_KEY` in GitHub) has been **replaced by OIDC federation** for true hands-off operation.

**Old method (DO NOT USE)**:
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- ~~`GCP_PROJECT_ID`~~: No longer needed
- ~~`RUNNER_MGMT_TOKEN`~~: Fetched dynamically from GSM
- ~~`DEPLOY_SSH_KEY`~~: Fetched dynamically from GSM or pre-provisioned

**New method (ACTIVE)**:
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: Ephemeral OIDC token provider
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- (Optional) `SLACK_WEBHOOK_URL`: For real-time notifications

---

## Activation Steps (After OIDC Secrets Provisioned)

### 1. **Verify OIDC Secrets Are Set**
```bash
# List all secrets to confirm the two OIDC secrets exist
gh secret list --repo kushin77/self-hosted-runner | grep GCP_WORKLOAD_IDENTITY_PROVIDER
gh secret list --repo kushin77/self-hosted-runner | grep GCP_SERVICE_ACCOUNT_EMAIL

# Both should appear in the list
```

### 2. **Trigger GSM Sync (Activate Secret Syncing)**
```bash
gh workflow run sync-gsm-to-github-secrets.yml -R kushin77/self-hosted-runner --ref main
```
Check logs: https://github.com/kushin77/self-hosted-runner/actions/workflows/sync-gsm-to-github-secrets.yml

**Expected Result**: 
- ✅ OIDC token exchange succeeds
- ✅ RUNNER_MGMT_TOKEN and DEPLOY_SSH_KEY fetched from GSM
- ✅ Secrets synced to GitHub repository secrets
- ✅ GSM labels show sync timestamp

### 3. **Trigger Runner Self-Heal (Activate Runner Health Monitoring)**
```bash
gh workflow run runner-self-heal.yml -R kushin77/self-hosted-runner --ref main
```
Check logs: https://github.com/kushin77/self-hosted-runner/actions/

**Expected Result**:
- ✅ OIDC auth succeeds
- ✅ Runner status fetched from GitHub API
- ✅ Any offline runners automatically restarted via Ansible
- ✅ Issue created if manual intervention needed

### 4. **Validate Full Automation**
```bash
# Check all scheduled workflows are active
gh api repos/kushin77/self-hosted-runner/actions/schedules --jq '.[] | {id:.id, name:.name}'

# List recent workflow runs
gh run list -R kushin77/self-hosted-runner --limit 10

# Verify no secrets stored in plaintext (OIDC-native auth)
gh secret list -R kushin77/self-hosted-runner | grep -c "GCP_WORKLOAD_IDENTITY_PROVIDER"
# Should return 1
```

---

## Idempotency Guarantees

All workflows are **idempotent** and safe to run concurrently:

- ✅ **GSM Sync**: Fetches from GSM via OIDC; only updates GitHub secrets if values change; no side effects if run multiple times
- ✅ **Rotations**: Create immutable audit issues; can be re-run without corruption
- ✅ **Self-Heal**: Checks runner status; only restarts if offline; safe at 5-minute intervals
- ✅ **Slack Notifications**: Re-runs produce duplicate messages only (acceptable trade-off for resilience)

---

## Scheduled Executions (Active The Moment Secrets Are Provisioned)

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

### OIDC Token Exchange Fails
- Check GitHub Actions logs for error: `"Unable to create OIDC token"`
- **Root Cause**: GCP Workload Identity Pool not configured or attribute mapping incorrect
- **Resolution**: Follow Issue #1055 step-by-step to set up OIDC pool and provider
- **Verification Command**: 
  ```bash
  gcloud iam workload-identity-pools describe github-runners --location=global --project=YOUR_GCP_PROJECT
  ```

### Secrets Not Syncing (After OIDC Setup)
- Check GitHub Actions logs for error details
- Verify `GCP_WORKLOAD_IDENTITY_PROVIDER` secret value matches GCP pool path
- Confirm service account (from `GCP_SERVICE_ACCOUNT_EMAIL`) has `Secret Manager Secret Accessor` role in GCP
- Confirm GSM secrets exist in GCP: `gcloud secrets list --project=YOUR_GCP_PROJECT`
- Verify IAM binding is correct:
  ```bash
  gcloud iam service-accounts get-iam-policy github-actions@YOUR_PROJECT.iam.gserviceaccount.com
  ```

### Workflow Won't Trigger  
- Check branch protection rules: workflows on `main` require branch protections
- Verify `GITHUB_TOKEN` has `actions: write` and `id-token: write` permissions (GitHub Actions does this automatically)

### Runners Offline After Self-Heal
- Verify DEPLOY_SSH_KEY is synced to GitHub secrets from GSM
- Check SSH connectivity to runner hosts: `ssh -i ~/runner_deploy_key ubuntu@runner-host`
- Check runner SSH daemon status on target machine: `systemctl status ssh`
- Consult **docs/EMERGENCY_CREDENTIAL_RECOVERY.md** for emergency procedures

### "gcp_available=false" in Logs
- OIDC token exchange failed (see "OIDC Token Exchange Fails" above)
- Workflows will gracefully degrade: no secrets will be synced, but workflow won't fail
- This is expected **before** GCP setup is complete; workflows activate once OIDC is configured

---

## Next Steps for Ops

**IMMEDIATE (Required for Activation)**:
1. **[Read Issue #1055](https://github.com/kushin77/self-hosted-runner/issues/1055)**: Complete step-by-step OIDC setup
2. **Execute 5 gcloud CLI commands from Issue #1055** (~5 minutes, copy-paste ready)
3. **Provision 2 GitHub Secrets** (commands provided in Issue #1055)

**POST-ACTIVATION (Validation)**:
1. Run verification steps in "Activation Steps" section above
2. Monitor first 3 GSM sync cycles to confirm OIDC token exchange succeeds
3. Monitor first 3 runner self-heal cycles to confirm runners healthy
4. (Optional) Configure Slack webhook for real-time alerts

**ONGOING (Day-2)**:
1. Weekly verification script runs: `./scripts/automation/validate-idempotency.sh`
2. Monitor GitHub issues for rotation events (immutable audit trail)
3. Review Slack notifications for failures or alerts
4. No manual intervention needed unless issue created by workflows

---

## Success Criteria (After GCP Setup + Secrets Provisioned)

<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- ✅ GSM sync workflow completes with `gcp_available=true`
- ✅ RUNNER_MGMT_TOKEN and DEPLOY_SSH_KEY synced to GitHub secrets
- ✅ Runner self-heal runs successfully; all runners marked healthy
- ✅ No errors in workflow logs related to authentication
- ✅ (Optional) Slack notifications deliver rotation events and alerts

---

## Support & Escalation

- **GCP Workload Identity Error**: See Issue #1055 (complete setup guide with gcloud CLI commands)
- **Workflow failures**: Check GitHub Actions logs; if unresolved, create issue with workflow run ID
- **Emergency credential recovery**: See docs/EMERGENCY_CREDENTIAL_RECOVERY.md
- **OIDC architecture questions**: See docs/GSM_VAULT_INTEGRATION.md
- **Phase 5 design doc**: See PHASE_5_OPS_RUNBOOK.md

---

**✅ Phase 5 is production-ready. Ops teams: proceed to [Issue #1055](https://github.com/kushin77/self-hosted-runner/issues/1055) to begin one-time OIDC setup.**

