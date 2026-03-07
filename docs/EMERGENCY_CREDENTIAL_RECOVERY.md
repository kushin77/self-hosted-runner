# Emergency Credential Recovery Procedures

**Last Updated**: March 7, 2026  
**Status**: ACTIVE  
**Owner**: @akushnir (ops-team)

## Overview

This runbook provides step-by-step procedures for handling compromised, leaked, or expired credentials in the self-hosted runner infrastructure. All procedures are designed to be **immutable, idempotent, and fully automated** where possible.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Immediate Response (First 5 Minutes)](#immediate-response-first-5-minutes)
3. [Short-term Actions (5-30 Minutes)](#short-term-actions-5-30-minutes)
4. [Medium-term Verification (1-2 Hours)](#medium-term-verification-1-2-hours)
5. [Long-term Audit (Post-Incident)](#long-term-audit-post-incident)
6. [Automated Recovery Workflows](#automated-recovery-workflows)

---

## Quick Reference

| Credential | Compromise Indicator | Immediate Action | Time to Recover |
|------------|---------------------|------------------|-----------------|
| `RUNNER_MGMT_TOKEN` | Unauthorized API calls in logs | Run `revoke-runner-mgmt-token` workflow | 5-10 min |
| `DEPLOY_SSH_KEY` | Unauthorized SSH connections | Run `revoke-deploy-ssh-key` workflow | 10-15 min |
| `VAULT_SECRET_ID` | Vault auth failures | Run `rotate-vault-approle` workflow | 5-10 min |
| `DOCKER_HUB_PAT` | Unauthorized Docker repo access | Revoke PAT in Docker Hub UI + run sync | 5 min |
| `GCP_SERVICE_ACCOUNT_KEY` | GCP API abuse | Disable service account key | 5 min |

---

## Immediate Response (First 5 Minutes)

### Step 1: Detect Compromise

**Signs of compromise:**
- Unexpected API calls from unknown IPs in GitHub API audit log
- Unauthorized runner registrations in GitHub
- Failed SSH login attempts from strange IP ranges
- Vault authentication failures
- Unauthorized Docker Hub push/pull operations
- GCP resource creation/deletion by unknown principals

**Detection command:**
```bash
# Check GitHub API activity (requires RUNNER_MGMT_TOKEN read access)
gh api repos/<owner>/<repo>/actions/runs \
  --jq '.workflow_runs[] | select(.created_at > "2026-03-07T00:00:00Z") | {id, name, created_at, event}'

# Check recent SSH attempts (on runner host)
sudo tail -50 /var/log/auth.log | grep -i "failed\|unauthorized"

# Check Vault login failures
vault audit list  # If you have access
```

### Step 2: Assess Exposure Scope

**Classify compromise level:**

- **CRITICAL** (immediate full revocation needed):
  - RUNNER_MGMT_TOKEN with admin:write scope
  - VAULT_SECRET_ID active and exploited
  - GCP service account key with broad IAM

- **HIGH** (revocation + monitoring):
  - DEPLOY_SSH_KEY
  - DOCKER_HUB_PAT
  - Individual Vault AppRole secret ID

- **MEDIUM** (rotation + monitoring):
  - Expired credentials still active
  - SSH keys with restricted scope
  - Docker Hub limited-repo access tokens

### Step 3: Activate Emergency Protocol

**Notify stakeholders:**
```bash
# Create critical issue in GitHub
gh issue create \
  --repo kushin77/self-hosted-runner \
  --title "🚨 CRITICAL: Credential Compromise Detected" \
  --body "Suspected compromise of [CREDENTIAL_NAME] detected at $(date -u) 
  
Scope: [CRITICAL|HIGH|MEDIUM]
Affected Service: [SERVICE_NAME]
Detection Method: [HOW_DETECTED]

Actions Taken:
- [ ] Credential immediately revoked/disabled
- [ ] Backup system activated
- [ ] Audit logs collected
- [ ] Stakeholders notified

See: Emergency Credential Recovery Procedures" \
  --label "critical,security,incident"

# Slack notification (if available)
# Message: "🚨 CRITICAL INCIDENT: Credentials potentially compromised. Recovery in progress."
```

---

## Short-term Actions (5-30 Minutes)

### Revoking RUNNER_MGMT_TOKEN

**If RUNNER_MGMT_TOKEN is compromised:**

```bash
# Manual revocation (if automation unavailable)
gh auth logout  # Current session
gh auth login   # Login with new credentials if available

# In GitHub UI:
# 1. Settings → Developer Settings → Personal Access Tokens (classic)
# 2. Find token with note "self-hosted-runner"
# 3. Click "Delete"

# Immediate action via workflow:
gh workflow run revoke-runner-mgmt-token.yml --repo kushin77/self-hosted-runner
```

**Workflow automation:**
- Creates issue tracking revocation
- Stops all running workflows (gracefully)
- Archives old token to GSM audit log
- Awaits manual creation of new token + operator approval

### Revoking DEPLOY_SSH_KEY

**If DEPLOY_SSH_KEY is compromised:**

```bash
# Remove public key from authorized_hosts on all runner hosts
# (For each runner host)
ssh -i ~/.ssh/admin_key runner@<RUNNER_HOST> << 'EOF'
  sudo sed -i '/<OLD_PUBLIC_KEY>/d' ~/.ssh/authorized_keys
  sudo systemctl restart sshd
EOF

# Immediate action via workflow:
gh workflow run revoke-deploy-ssh-key.yml --repo kushin77/self-hosted-runner
```

**Workflow automation:**
- Connects to each runner via fallback admin key
- Removes old public key from authorized_keys
- Generates new ED25519 keypair
- Stores in GSM under deploy-ssh-key
- Updates GitHub Secrets
- Tests connectivity with new key

### Rotating VAULT_SECRET_ID

**If VAULT_SECRET_ID is compromised:**

```bash
# Via Vault CLI (if direct access available)
vault write -f auth/approle/role/gh-runner/secret-id lookup/destroy \
  secret_id="<COMPROMISED_SECRET_ID>"

# Via workflow automation (preferred):
gh workflow run rotate-vault-approle.yml \
  --repo kushin77/self-hosted-runner \
  --ref main
```

**Workflow automation:**
- Authenticates to Vault with current SECRET_ID
- Generates new SECRET_ID
- Updates GitHub Secrets
- Archives audit log
- Notifies ops team

---

## Medium-term Verification (1-2 Hours)

### Verify Revocation Success

**Check GitHub API:**
```bash
# Verify runner still operational
gh api repos/<owner>/<repo>/actions/runners | jq '.runners[] | {id, name, status, busy}'

# Check recent workflow runs
gh api repos/<owner>/<repo>/actions/runs --jq '.workflow_runs[0:5] | .[] | {id, status, conclusion}'
```

**Check runner connectivity:**
```bash
# SSH test
ssh -i ~/.ssh/new_key runner@<RUNNER_HOST> "echo 'SSH connection OK'"

# Self-heal trigger (verify automation is responsive)
gh workflow run runner-self-heal.yml \
  --repo kushin77/self-hosted-runner \
  --ref main
```

**Check Vault access:**
```bash
# Verify AppRole can authenticate with new SECRET_ID
curl -s -X POST \
  -d '{"role_id":"'$VAULT_ROLE_ID'","secret_id":"'$NEW_SECRET_ID'"}' \
  $VAULT_ADDR/v1/auth/approle/login | jq '.auth.client_token'
```

### Monitor for Residual Attacks

**Watch for:**
- Continued failures with old credentials (indicates compromise attempt)
- New runner registrations from unknown IPs
- Unusual workflow execution patterns
- Vault auth failures post-rotation

**Set up alerts (GitHub Issues bot):**
```bash
# Configured in credential-monitor workflow
# Creates issue if RUNNER_MGMT_TOKEN attempts fail 3+ times
# Auto-description includes recovery procedures
```

---

## Long-term Audit (Post-Incident)

### Forensic Analysis

1. **Collect audit logs:**
   ```bash
   # GitHub Actions audit log (Settings → Audit log)
   # Export timeframe: [COMPROMISE_TIME] to now
   
   # Vault audit log (if available)
   vault audit list
   vault read -format=json sys/audit | jq '.data'
   
   # GCP Cloud Audit Logs
   gcloud logging read \
     "resource.type=secretmanager.googleapis.com AND \
      timestamp>[COMPROMISE_TIME]" \
     --limit=1000 \
     --format=json > gcp-audit.json
   ```

2. **Analyze access patterns:**
   - Which APIs were called with revoked credentials?
   - Which services were accessed?
   - Did any secrets leak?

3. **Create incident report:**
   ```bash
   gh issue create \
     --repo kushin77/self-hosted-runner \
     --title "📋 Post-Incident Report: [CREDENTIAL_NAME] Compromise" \
     --body "## Incident Analysis
   
Compromise Detected: [TIMESTAMP]
Time to Containment: [MINUTES]
Estimated Exposure: [DESCRIPTION]

### Root Cause Analysis
[ANALYSIS]

### Lessons Learned
1. [LESSON_1]
2. [LESSON_2]

### Preventive Actions
- [ ] Enable MFA on GitHub account
- [ ] Reduce token TTL
- [ ] Implement IP whitelisting
- [ ] Enable Vault secret audit
- [ ] Automated secret rotation frequency"
   ```

### Credential Recertification

**After incident resolution:**

1. **Rotate all credentials proactively** (don't wait for next monthly rotation):
   ```bash
   gh workflow run credential-rotation-monthly.yml \
     --repo kushin77/self-hosted-runner \
     --input rotate_runner_token=true \
     --input rotate_ssh_key=true \
     --input rotate_vault_approle=true
   ```

2. **Verify all systems functioning:**
   - Run E2E tests
   - Monitor for 24 hours
   - Document any anomalies

3. **Update this runbook:**
   - Record what worked
   - Update detection thresholds
   - Improve automation

---

## Automated Recovery Workflows

### Available Workflows

| Workflow | Trigger | Purpose | RTO |
|----------|---------|---------|-----|
| `revoke-runner-mgmt-token.yml` | Manual/auto | Disable compromised GitHub PAT | 5m |
| `revoke-deploy-ssh-key.yml` | Manual/auto | Remove SSH key from runners | 15m |
| `rotate-vault-approle.yml` | Schedule/manual | Generate new Vault credentials | 10m |
| `credential-rotation-monthly.yml` | Schedule/manual | Rotate all credentials | 20m |
| `credential-monitor.yml` | Every 5 min | Detect credential absence/failure | Continuous |
| `runner-self-heal.yml` | On-demand | Recover failed runner | 10m |

### Triggering Recovery Workflows

**Via CLI (fastest):**
```bash
# Immediate revocation
gh workflow run revoke-runner-mgmt-token.yml --repo kushin77/self-hosted-runner

# With inputs
gh workflow run credential-rotation-monthly.yml \
  --repo kushin77/self-hosted-runner \
  --input rotate_vault_approle=true
```

**Via GitHub UI:**
1. Navigate to Actions tab
2. Click workflow name
3. Click "Run workflow"
4. Select branch and inputs
5. Click "Run workflow"

---

## Testing the Runbook

**Monthly DR test includes credential recovery:**

```bash
# Simulate compromise (safe test environment)
gh workflow run monthly-disaster-recovery-test.yml \
  --repo kushin77/self-hosted-runner \
  --input scenario=credential-compromise
```

**Expected test results:**
- ✅ Token revoked in <5 min
- ✅ Self-heal workflow reactivates system
- ✅ New token provisioned from GSM
- ✅ All workflows passing with new creds

---

## Escalation Path

If automated recovery fails:

1. **Immediate** (0-5 min):
   - Create critical GitHub issue
   - Notify ops-team
   - Manual review of logs

2. **Short-term** (5-30 min):
   - Trigger manual workflow runs
   - Verify DNS, network, Vault availability
   - Check GitHub Actions quotas

3. **Escalation** (30+ min):
   - Contact GitHub Support (runner issues)
   - Contact GCP Support (GSM access)
   - Contact HashiCorp Support (Vault)
   - Manual credential recovery via backup procedures

---

## References

- [GitHub Credentials Security](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [GCP Secret Manager](https://cloud.google.com/secret-manager/docs)
- [Vault AppRole Auth](https://www.vaultproject.io/docs/auth/approle)
- [SSH Key Management Best Practices](https://linux.die.net/man/1/ssh-keygen)
- [Main Runbook](../ROADMAP.md) — Full system operations

---

**Document ID**: EMERGENCY_CREDENTIAL_RECOVERY  
**Classification**: Internal — Operational Procedures  
**Retention**: 7 years (compliance requirement)  
**Last Review**: March 7, 2026
