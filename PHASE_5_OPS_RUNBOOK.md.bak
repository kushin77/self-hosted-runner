# Phase 5 Operations Runbook

**Status**: ACTIVE (2026-03-07)  
**Owner**: @akushnir, @ops-team  
**Last Updated**: 2026-03-07  

## Table of Contents

1. [Overview](#overview)
2. [Credential Management](#credential-management)
3. [Self-Heal Operations](#self-heal-operations)
4. [Disaster Recovery](#disaster-recovery)
5. [Monitoring & Alerts](#monitoring--alerts)
6. [Incident Response](#incident-response)
7. [Compliance & Audit](#compliance--audit)

---

## Overview

This runbook covers operational procedures for the immutable, ephemeral, idempotent, fully automated self-hosted runner system.

### System Architecture

```
┌─────────────────────────────────────────────────────────┐
│ GitHub Actions Workflows (CI/CD)                        │
├─────────────────────────────────────────────────────────┤
↓                                                           ↓
GCP Secret Manager (GSM)        ← → Vault AppRole
(Primary credentials store)          (Dynamic rotation)
↓
GitHub Actions (Repository Secrets)
↓
├─ RUNNER_MGMT_TOKEN (GitHub PAT)
├─ DEPLOY_SSH_KEY (SSH private key)
├─ VAULT_ADDR, VAULT_NAMESPACE
└─ SLACK_WEBHOOK_URL (for alerts)
↓
Automated Workflows:
├─ Sync GSM → GitHub (every 6 hours)
├─ Runner Self-Heal (every 5 minutes)
├─ Credential Rotation (monthly)
└─ Vault AppRole Rotation (quarterly)
```

### Key Properties

| Property | Status | Details |
|----------|--------|---------|
| **Immutable** | ✅ | All critical data versioned in GitHub and archived in immutable storage |
| **Ephemeral** | ✅ | Runner instances and temporary artifacts are stateless |
| **Idempotent** | ✅ | Workflows are safe to re-run; no duplicate side effects |
| **Fully Automated** | ✅ | No manual intervention required after initial secret setup |
| **Hands-Off** | ✅ | Workflows execute autonomously and post results automatically |

---

## Credential Management

### 1. Setting Up GCP Secret Manager (Initial)

#### Prerequisites

- GCP Project with Secret Manager API enabled
- Service account with `secretmanager.secretAccessor` role
- `gcloud` CLI configured

#### Steps

```bash
# 1. Authenticate with GCP
gcloud auth login
gcloud config set project YOUR_GCP_PROJECT_ID

# 2. Create secrets for runner management
echo -n "ghp_your_runner_pat_here" | \
  gcloud secrets create runner-mgmt-token --data-file=-

echo -n "$(cat ~/.ssh/id_ed25519)" | \
  gcloud secrets create deploy-ssh-key --data-file=-

# 3. Create secrets for MinIO/backup (optional)
echo -n "http://mc.elevatediq.ai:9000" | \
  gcloud secrets create minio-endpoint --data-file=-

echo -n "minioadmin" | \
  gcloud secrets create minio-access-key --data-file=-

echo -n "your_secret_key" | \
  gcloud secrets create minio-secret-key --data-file=-

# 4. Grant service account access
SA_EMAIL=$(gcloud config get-value core/project)@iam.gserviceaccount.com

for SECRET in runner-mgmt-token deploy-ssh-key minio-endpoint minio-access-key minio-secret-key; do
  gcloud secrets add-iam-policy-binding "$SECRET" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/secretmanager.secretAccessor"
done

# 5. Verify secrets are accessible
gcloud secrets list --filter="name:(runner-mgmt-token OR deploy-ssh-key)"
```

### 2. Adding GitHub Service Account for Automated Sync

```bash
# Get the service account key (JSON format)
gcloud iam service-accounts keys create ~/gcp-sa-key.json \
  --iam-account=YOUR_SERVICE_ACCOUNT_EMAIL

# Add to GitHub Secrets
gh secret set GCP_SERVICE_ACCOUNT_KEY \
  --repo kushin77/self-hosted-runner \
  --body "$(cat ~/gcp-sa-key.json)"

# Also set the project ID
gh secret set GCP_PROJECT_ID \
  --repo kushin77/self-hosted-runner \
  --body "YOUR_GCP_PROJECT_ID"

# Clean up local copy
rm ~/gcp-sa-key.json
```

### 3. Verifying Secrets Are Synced

```bash
# List repository secrets
gh secret list --repo kushin77/self-hosted-runner

# Expected output:
# RUNNER_MGMT_TOKEN          No description
# DEPLOY_SSH_KEY             No description
# GCP_SERVICE_ACCOUNT_KEY    No description
# GCP_PROJECT_ID             No description
```

### 4. Manual Secret Rotation (Emergency)

If you need to rotate a secret immediately:

```bash
# Rotate RUNNER_MGMT_TOKEN
NEW_PAT="ghp_your_new_pat"
gh secret set RUNNER_MGMT_TOKEN \
  --repo kushin77/self-hosted-runner \
  --body "$NEW_PAT"

# Update in GSM
echo -n "$NEW_PAT" | \
  gcloud secrets versions add runner-mgmt-token --data-file=-

# Revoke old PAT (via GitHub Settings → Developer settings → Personal access tokens)
# Then document in audit log:
# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Action: Manual rotation of RUNNER_MGMT_TOKEN
# Reason: <describe reason>
```

### 5. Vault AppRole Setup (Optional)

```bash
# Ensure Vault CLI is installed
vault version

# Configure Vault address
export VAULT_ADDR=https://vault.example.com
export VAULT_NAMESPACE=admin

# Login with GitHub OIDC
vault login -method=oidc role=gh-runner

# Create AppRole for runner automation
vault auth enable approle
vault policy write runner-policy - <<EOF
path "secret/data/runner/*" {
  capabilities = ["read", "list"]
}
path "kv/data/runner/*" {
  capabilities = ["read", "list"]
}
EOF

vault write auth/approle/role/gh-runner \
  token_ttl=3600 \
  token_max_ttl=86400 \
  policies="runner-policy"

# Get role ID and create secret ID
ROLE_ID=$(vault read -field=role_id auth/approle/role/gh-runner/role-id)
SECRET_ID=$(vault write -field=secret_id auth/approle/role/gh-runner/secret-id ttl=7d)

# Store in GitHub secrets
gh secret set VAULT_ROLE_ID --repo kushin77/self-hosted-runner --body "$ROLE_ID"
gh secret set VAULT_SECRET_ID --repo kushin77/self-hosted-runner --body "$SECRET_ID"
gh secret set VAULT_ADDR --repo kushin77/self-hosted-runner --body "$VAULT_ADDR"
gh secret set VAULT_NAMESPACE --repo kushin77/self-hosted-runner --body "$VAULT_NAMESPACE"
```

---

## Self-Heal Operations

### 1. Triggering Manual Self-Heal

```bash
# Dispatch the runner-self-heal workflow
gh workflow run runner-self-heal.yml \
  --repo kushin77/self-hosted-runner

# Monitor the run
gh run list --repo kushin77/self-hosted-runner \
  --workflow=runner-self-heal.yml --limit 5

# View detailed logs
RUN_ID=$(gh run list --repo kushin77/self-hosted-runner \
  --workflow=runner-self-heal.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view $RUN_ID --repo kushin77/self-hosted-runner --log
```

### 2. Monitoring Self-Heal Status

```bash
# Check if runners are online
gh api /repos/kushin77/self-hosted-runner/actions/runners \
  --jq '.runners[] | {name, status, busy}'

# Expected output (healthy):
# {
#   "name": "runner-1",
#   "status": "online",
#   "busy": false
# }
```

### 3. Debugging Failed Self-Heals

```bash
# 1. Check recent workflow runs
gh run list --repo kushin77/self-hosted-runner \
  --workflow=runner-self-heal.yml \
  --limit 10 --json status,name,updatedAt

# 2. Get detailed error logs
gh run view FAILED_RUN_ID \
  --repo kushin77/self-hosted-runner \
  --log | grep -A 10 "error\|Error\|ERROR"

# 3. Check if secrets are present
gh secret list --repo kushin77/self-hosted-runner

# 4. If RUNNER_MGMT_TOKEN missing: Sync from GSM
gh workflow run sync-gsm-to-github-secrets.yml \
  --repo kushin77/self-hosted-runner

# 5. Verify Ansible inventory
cat ansible/inventory/staging
```

### 4. If Self-Heal Still Fails (Manual Recovery)

```bash
# 1. SSH into runner host
ssh -i ~/.ssh/id_ed25519 runner@runner-1.example.com

# 2. Check runner agent status
cd ~/actions-runner
./svc.sh status

# 3. Restart the agent
sudo ./svc.sh stop
sudo ./svc.sh start

# 4. Verify it's back online
# (check "runners are online" check from step 2 above)

# 5. Create incident issue
gh issue create --repo kushin77/self-hosted-runner \
  --title "Manual runner recovery performed" \
  --body "Runner: runner-1
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Action: Manual restart via SSH
Status: Online
Next: Review logs and identify automation failure cause" \
  --label "incident,ops,manual-action"
```

---

## Disaster Recovery

### 1. Weekly DR Test Execution

The system performs automated DR tests every Tuesday at 3 AM UTC. Monitor the test:

```bash
# Check latest DR test run
gh run list --repo kushin77/self-hosted-runner \
  --workflow=docker-hub-weekly-dr-testing.yml --limit 5

# View detailed results
gh run view LATEST_RUN_ID \
  --repo kushin77/self-hosted-runner --log

# Download test artifacts
gh run download LATEST_RUN_ID \
  --repo kushin77/self-hosted-runner \
  --dir ./dr-test-artifacts
```

### 2. Manual DR Test (On-Demand)

```bash
# Trigger manual DR test
gh workflow run docker-hub-weekly-dr-testing.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f backup_tag=latest-backup \
  -f dry_run=false

# Monitor progress
RUN_ID=$(gh run list --repo kushin77/self-hosted-runner \
  --workflow=docker-hub-weekly-dr-testing.yml --limit 1 --json databaseId --jq '.[0].databaseId')
watch -n 5 "gh run view $RUN_ID --repo kushin77/self-hosted-runner | grep -E 'Status|Conclusion'"
```

### 3. DR Dry-Run (Safe Testing)

```bash
# Run DR test in dry-run mode (no destructive actions)
gh workflow run docker-hub-weekly-dr-testing.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f dry_run=true

# Safe to run without GCP secrets configured
```

### 4. Actual Disaster Recovery (If Needed)

```bash
# Step 1: Trigger full DR with verbose logging
gh workflow run docker-hub-weekly-dr-testing.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f verbose=true \
  -f dry_run=false

# Step 2: Monitor recovery progress
gh run view $RUN_ID --repo kushin77/self-hosted-runner --log | tail -50

# Step 3: Verify restored system
./scripts/verify-recovery.sh docker.io/elevatediq/app-backup:latest-backup

# Step 4: Promote restored backup to production
# (See recovery script output for promotion commands)

# Step 5: Document incident
gh issue create --repo kushin77/self-hosted-runner \
  --title "🚨 Disaster Recovery Event - $(date -u +%Y-%m-%d)" \
  --body "## Incident Summary
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Trigger: [describe what caused the need for DR]
Duration: [measure recovery time]
Impact: [describe services/data affected]

## Actions Taken
1. Triggered DR workflow
2. Verified backup integrity
3. Promoted restored system
4. Verified functionality

## Post-Incident
- Root cause: [TBD]
- Preventive measures: [TBD]
- Runbook updates: [TBD]" \
  --label "incident,disaster-recovery"
```

---

## Monitoring & Alerts

### 1. Setting Up Slack Notifications

```bash
# 1. Create Slack webhook
# In Slack workspace → Apps → Incoming Webhooks → New Webhook
# Copy the webhook URL

# 2. Add to GitHub Secrets
gh secret set SLACK_WEBHOOK_URL \
  --repo kushin77/self-hosted-runner \
  --body "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 3. Verify notification workflow is active
gh workflow list --repo kushin77/self-hosted-runner | grep slack-notifications
```

### 2. Critical Alert Topics

The system automatically sends Slack alerts for:

- ✅/❌ Runner Self-Heal completion
- ✅/❌ Weekly DR Test results (critical if failed)
- 🔄 Credential Rotation events
- 🔐 Vault AppRole Rotation
- 🚨 Critical GitHub issues

### 3. Monitoring Dashboard

Create a monitoring dashboard to track:

```bash
# Self-heal success rate
gh workflow run list--repo kushin77/self-hosted-runner \
  --workflow=runner-self-heal.yml --limit 100 \
  | grep -c "success"

# DR test success rate
gh run list --repo kushin77/self-hosted-runner \
  --workflow=docker-hub-weekly-dr-testing.yml --limit 52 \
  | grep -c "success"

# Outstanding critical issues
gh issue list --repo kushin77/self-hosted-runner \
  --label critical --state open
```

---

## Incident Response

### 1. Self-Heal Failure

**Symptoms**: Runner status remains offline after 5-minute cycles  
**Detection**: Slack alert + GitHub issue

**Steps**:
1. Check RUNNER_MGMT_TOKEN presence: `gh secret list`
2. If missing, trigger GSM sync: `gh workflow run sync-gsm-to-github-secrets.yml`
3. If present, check for API 403: `gh run view <RUN_ID> --log | grep "403\|Forbidden"`
4. If 403, verify PAT has `administration:read` scope
5. If 404, verify repo slug and runner existence
6. Manual recovery: SSH into host and restart agent

### 2. Credential Compromise

**Symptoms**: Unauthorized access detected  
**Steps**:
1. Immediately revoke compromised credential:
   ```bash
   # Revoke GitHub PAT
   gh api user/keys/DELETE /repos/OWNER/REPO/keys/KEY_ID
   
   # Revoke SSH key from runners
   # SSH into each runner and remove from ~/.ssh/authorized_keys
   ```
2. Generate new credential
3. Update GSM and GitHub Secrets
4. Rotate Vault AppRole (if applicable)
5. Create incident issue
6. Notify team via Slack

### 3. DR Test Failure

**Symptoms**: DR weekly test fails; backup integrity questionable  
**Steps**:
1. Trigger manual DR test with verbose logging
2. Download artifacts and review logs
3. Check backup image integrity in Docker Hub
4. If image corrupted, restore from secondary archive (MinIO)
5. Document findings in issue

---

## Compliance & Audit

### 1.  Auditing Credential Rotation

All credential rotations are logged in GitHub issues. To retrieve audit trail:

```bash
gh issue list --repo kushin77/self-hosted-runner \
  --label rotation --state all --limit 500 \
  --json title,createdAt,state | jq '.[] | select(.title | contains("Rotation"))'
```

### 2. Compliance Report Generation

```bash
# Generate monthly compliance report
cat > COMPLIANCE_ROTATION_REPORT_$(date +%Y-%m).md <<'EOF'
# Credential Rotation Compliance Report — $(date +%B %Y)

## Summary
- Monthly rotation: ✅ Executed
- Quarters rotation: ✅ On schedule
- Audit trail: ✅ Complete
- Documentation: ✅ Updated

## Rotations Performed
$(gh issue list --repo kushin77/self-hosted-runner --label rotation --state all --search "created:>$(date -d '1 month ago' +%Y-%m-%d)" --json title,createdAt | jq -r '.[] | "- \(.title) (\(.createdAt | split("T")[0]))"')

## Compliance Checklist
- [ ] All credentials rotated on schedule
- [ ] No stale credentials in use
- [ ] Emergency revocation procedures documented
- [ ] Team training completed
- [ ] Audit logs archived
- [ ] 7-year retention verified

## Sign-Off
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Signed by: [ops-team]
EOF
```

### 3. Disaster Recovery Readiness Checklist

Monthly, verify:

```bash
# ✅ DR test passes
gh run list --repo kushin77/self-hosted-runner \
  --workflow=docker-hub-weekly-dr-testing.yml --limit 4 \
  | grep "success" | wc -l
# Should show 4 (4 weeks passing)

# ✅ Backup images exist
gcloud container images list-tags gcr.io/YOUR_PROJECT/app-backup

# ✅ All credentials synced
gh secret list --repo kushin77/self-hosted-runner | wc -l
# Should show at least 10 secrets

# ✅ Self-heal success rate > 95%
# (Track in dashboard from step 3 above)

# ✅ Documentation current
git log -n 1 --oneline docs/ ansible/ scripts/
```

---

## Runbook Maintenance

This runbook is version-controlled and updated automatically when:
- New workflows are deployed
- New incidents occur
- Compliance requirements change
- Quarterly reviews occur

**Last Review**: 2026-03-07  
**Next Review**: 2026-06-07  
**Owner**: @akushnir
