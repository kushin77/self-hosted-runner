# 🔐 Secrets Operations Guide (10X Enhancement)

**Your complete reference for securely provisioning, using, rotating, and troubleshooting secrets in this repository.**

---

## Quick Navigation

| Need | Link |
|------|------|
| 🚀 **First time? Start here** | [5-Minute Quick Start](#quick-start-5-minutes) |
| 📋 **All secrets listed** | [SECRETS_CLASSIFICATION.yml](./SECRETS_CLASSIFICATION.yml) |
| 🔄 **Rotate a secret** | [Rotation Procedures](#rotation-procedures) |
| 🐛 **Something's broken** | [Troubleshooting](#troubleshooting) |
| 🚨 **Security incident** | [Emergency Response](#emergency-response) |
| 👤 **I need access** | [Access Control & RBAC](#access-control--rbac) |

### Scenario 1: I need to set a new secret

```bash
# 1. Choose your method (CLI is faster)
gh secret set MY_SECRET_NAME  # Interactive: prompts for value
# OR
gh secret set MY_SECRET_NAME --body "my-secret-value"

# 2. Verify it was set
gh secret list --repo kushin77/self-hosted-runner | grep MY_SECRET_NAME

# 3. Reference in workflow
# In .github/workflows/my-workflow.yml:
# env:
```
### Scenario 2: I broke something with secrets

# Find what went wrong
gh run list --limit 5 --json name,conclusion | jq '.[] | select(.conclusion=="failure")'

# View the failure
gh run view <RUN_ID> --log-failed
# Common issues:
# ❌ Secret not set → Follow: https://github.com/kushin77/self-hosted-runner#quick-start
# ❌ Secret value wrong → Validate with jq: jq . < /path/to/file.json
# ❌ Secret expired → Check expiration in SECRETS_CLASSIFICATION.yml
```
### Scenario 3: My secret is about to rotate
```bash
# Check what needs rotating
grep "next_rotation_due:" SECRETS_CLASSIFICATION.yml | grep "202[6]"

# Follow the rotation procedure
# → [Rotation Procedures](#rotation-procedures)

# The system will alert you 14 days before expiration
```

---

## Secret Tiers & Criticality

Secrets are classified into **5 tiers** by access level and criticality:

### 🔴 TIER 1: Infrastructure Authentication (CRITICAL)
- **Examples**: GCP_SERVICE_ACCOUNT_KEY, DEPLOY_SSH_KEY, RUNNER_MGMT_TOKEN
- **Access**: GitHub Actions workflows only (bot-only)
- **Rotation**: Every 90 days (mandatory)
- **If invalid**: Blocking issue auto-created, workflows skipped
- **Exposure risk**: Can destroy infrastructure → immediate response

### 🟠 TIER 2: Container Registry (HIGH)
- **Examples**: DOCKER_HUB_PAT, DOCKER_HUB_USERNAME
- **Access**: CI/CD workflows
- **Rotation**: Every 60 days (mandatory)
- **If invalid**: Images can't be pushed → pipeline blocked
- **Exposure risk**: Attacker can push malicious images

### 🟠 TIER 3: Secrets Management (HIGH)
- **Examples**: VAULT_ROLE_ID, VAULT_SECRET_ID, MINIO_ACCESS_KEY
- **Access**: Bot-only
- **Rotation**: Every 90 days
- **If invalid**: Artifact storage/secrets management fails
- **Exposure risk**: Lateral movement to all systems

### 🟡 TIER 4: Integrations (MEDIUM)
- **Examples**: SLACK_WEBHOOK_URL
- **Access**: Notification workflows
- **Rotation**: Every 180 days
- **If invalid**: Alerts can't send (but infra still works)
- **Exposure risk**: Attacker can spam Slack with fake alerts

### 🟠 TIER 5: Infrastructure Config (HIGH)
- **Examples**: STAGING_KUBECONFIG
- **Access**: Deployment workflows
- **Rotation**: On-demand (when cluster rotates certs)
- **If invalid**: Deployments fail
- **Exposure risk**: Cluster compromise

---

## Rotation Procedures

### 🔄 Automated Rotation (Hands-Off)

Most secrets rotate **automatically** on schedule:

```bash
# Check if a secret is auto-rotating
grep "rotation_days:" SECRETS_CLASSIFICATION.yml | grep -v "never"

# Workflows that handle auto-rotation:
ls -1 .github/workflows/*rotation*.yml
# - credential-rotation-monthly.yml (runs 1st of month)
# - vault-approle-rotation-quarterly.yml (runs 1st of quarter)
# - docker-hub-auto-secret-rotation.yml (runs 1st of month)
# - secret-rotation-mgmt-token.yml (runs 1st of month + on-demand)
```

**What happens:**
1. Workflow runs on schedule → generates new secret
2. Updates GitHub secret automatically
3. Logs rotation to ROTATION_LOG.md
4. Posts Slack notification ✅
5. If rotation fails → creates blocking issue + pages on-call

### 🔄 Manual Rotation (Operator-Initiated)

For secrets that don't auto-rotate or for emergency rotation:

#### Step 1: Generate New Secret

**For GCP Service Account Key:**
```bash
gcloud iam service-accounts keys create key.json \
  --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com

# Validate JSON
jq . key.json  # Must output valid JSON, not errors

# Check key fields
jq '{type, project_id, private_key: "***"}' key.json

# Copy full JSON content
cat key.json | xclip  # Linux
# or
cat key.json | pbcopy  # macOS
```

**For GitHub PAT (RUNNER_MGMT_TOKEN):**
```bash
# Option A: Web UI (recommended)
# Go to: https://github.com/settings/tokens/new
# - Token name: runner-management-automation-2026-03-XX
# - Expiration: 90 days
# - Scopes: repo, admin:repo_hook, admin:org_hook
# - Click "Generate token" → copy immediately

# Option B: Via GitHub CLI (if you have existing PAT)
gh auth token  # Get your current token
# Then create new one via web UI (can't create PAT from CLI without existing token)
```

**For SSH Key (DEPLOY_SSH_KEY):**
```bash
ssh-keygen -t ed25519 \
  -C "runner-deploy-automation" \
  -f ~/.ssh/runner_deploy_key_$(date +%Y%m%d) \
  -N ""  # No passphrase

cat ~/.ssh/runner_deploy_key_YYYYMMDD | xclip  # Private key
cat ~/.ssh/runner_deploy_key_YYYYMMDD.pub      # Public key (for runner hosts)
```

**For Docker Hub PAT:**
```bash
# Go to: https://hub.docker.com/account/personal-access-tokens/create
# - Token name: ci-automation-2026-03
# - Access permissions: Read & Write
# - Click "Create" → copy token

# Validate it works
echo "<TOKEN>" | docker login --username kushin77-bot --password-stdin

# Logout
docker logout
```

#### Step 2: Update Secret in GitHub

```bash
# Method A: GitHub CLI (fastest)
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# Method B: GitHub Web UI
# 1. Go to: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions
# 2. Click "New repository secret"
# 3. Name: <SECRET_NAME>
# 4. Value: <paste-entire-value>
# 5. Click "Add secret"

# Method C: GitHub CLI with stdin
gh secret set MY_SECRET --repo kushin77/self-hosted-runner --body "$(cat /path/to/file)"
```

#### Step 3: Validate & Test

```bash
# 1. Verify secret exists
gh secret list --repo kushin77/self-hosted-runner | grep GCP_SERVICE_ACCOUNT_KEY

# 2. Run validation workflow
gh workflow run verify-secrets-and-diagnose.yml --ref main

# 3. Check results
gh run list --workflow=verify-secrets-and-diagnose.yml --limit 1

# 4. If validation fails
gh run view <RUN_ID> --log
# → Follow troubleshooting section
```

#### Step 4: Update Associated Secrets

Some secrets **must stay in sync**:

```bash
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# 1. GCP_PROJECT_ID (should match service account)
# 2. GCP_SERVICE_ACCOUNT_EMAIL (should match service account)
# 3. TF_VAR_SERVICE_ACCOUNT_KEY (must be identical copy)

# Validate sync
jq -r '.project_id' key.json  # Compare to GCP_PROJECT_ID
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
```

#### Step 5: Log the Rotation

```bash
# Edit ROTATION_LOG.md
cat >> ROTATION_LOG.md << 'EOF'
## [$(date -u +%Y-%m-%d)] GCP_SERVICE_ACCOUNT_KEY - Manual Rotation

**Operator:** @your-username  
**Reason:** Scheduled 90-day rotation  
**Status:** ✅ Complete  

- Generated new service account key via gcloud CLI
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- Validated with: gh workflow run verify-secrets-and-diagnose.yml
- Affected workflows notified: docker-hub-weekly-dr-testing.yml, terraform-plan-ami.yml
- Backup: Old key rotated out (expires 2026-03-07)

---
EOF

git add ROTATION_LOG.md
git commit -m "docs: log GCP_SERVICE_ACCOUNT_KEY manual rotation [$(date -u +%Y-%m-%d)]"
git push origin main
```

---

## Validation Checklist

Use this daily/weekly to ensure secrets health:

```bash
#!/bin/bash
# Save as: scripts/validate-secrets.sh
# Run: ./scripts/validate-secrets.sh

set -e

REPO="kushin77/self-hosted-runner"
CRITICAL_SECRETS=(
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
  "GCP_PROJECT_ID"
  "RUNNER_MGMT_TOKEN"
  "DEPLOY_SSH_KEY"
  "VAULT_ROLE_ID"
  "VAULT_SECRET_ID"
)

echo "🔍 Validating critical secrets..."

for SECRET in "${CRITICAL_SECRETS[@]}"; do
  VALUE=$(gh secret list --repo "$REPO" --json name | jq -r ".[] | select(.name==\"$SECRET\")")
  
  if [ -z "$VALUE" ]; then
    echo "❌ $SECRET: MISSING"
    exit 1
  else
    echo "✅ $SECRET: Present"
  fi
done

echo ""
echo "✅ All critical secrets present!"
echo ""
echo "⏰ Checking rotation status..."

# Check for overdue rotations (simplified)
gh run list --workflow=credential-rotation-monthly.yml --limit 3 --json conclusion

echo ""
echo "✅ Validation complete!"
```

---

## Troubleshooting

### ❌ "Secret not found" in workflow

**Symptoms:**
```
Error: Secrets.SECRET_NAME not found. Available secrets: ...
```

**Solution:**
```bash
# 1. Verify secret exists
gh secret list --repo kushin77/self-hosted-runner | grep SECRET_NAME

# 2. If missing, create it
gh secret set SECRET_NAME --body "value-here"

# 3. Check workflow syntax
grep "secrets.SECRET_NAME" .github/workflows/my-workflow.yml
# Should be: ${{ secrets.SECRET_NAME }}
```

### ❌ Secret value is wrong format

**Symptoms:**
```
error: failed to parse service account key JSON credentials: unexpected end of JSON input
```

**Solution:**
```bash
# 1. Validate JSON locally BEFORE setting
jq empty < /path/to/key.json  # Must output nothing if valid

# 2. If invalid, check file
head -20 /path/to/key.json  # Is it truncated?
tail -20 /path/to/key.json  # Missing closing brace?

# 3. Re-download/generate the secret
gcloud iam service-accounts keys create key-new.json \
  --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com

# 4. Validate and update
jq empty < key-new.json  # Must be valid
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# 5. Test
gh workflow run verify-secrets-and-diagnose.yml --ref main
```

### ❌ Secret expired or about to expire

**Symptoms:**
```
Warning: Secret expires in 7 days (2026-06-03)
OR
Error: Invalid auth token (expired)
```

**Solution:**
```bash
# 1. Check expiration
grep "next_rotation_due:" SECRETS_CLASSIFICATION.yml | grep RUNNER_MGMT_TOKEN

# 2. For PATs (GitHub, Docker Hub, Vault)
# Go to the service's settings and create a new token
# (See [Rotation Procedures](#rotation-procedures) above)

# 3. Update secret
gh secret set RUNNER_MGMT_TOKEN --body "ghp_NewTokenHere"

# 4. Validate
gh workflow run verify-secrets-and-diagnose.yml --ref main
```

### ❌ Rotation workflow failed

**Symptoms:**
```
Workflow: credential-rotation-monthly.yml
Status: ❌ Failed
```

**Solution:**
```bash
# 1. Check failure logs
gh run list --workflow=credential-rotation-monthly.yml --limit 1
gh run view <RUN_ID> --log-failed

# 2. Common reasons:
#    a) Upstream service (e.g. GCP) is down
#    b) Insufficient permissions (e.g. IAM scope)
#    c) Invalid credentials being used

# 3. Manual rotation as backup
# → Follow [Manual Rotation](#rotation-procedures) section

# 4. Check ROTATION_LOG.md for history
tail -50 ROTATION_LOG.md
```

### ❌ Someone accidentally exposed a secret in Git

**Symptoms:**
```
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
```

**IMMEDIATE ACTIONS (DO NOT DELAY):**

```bash
# 1. Create emergency issue
gh issue create \
  --title "[SECURITY] URGENT: Secret exposed in Git" \
  --label "security,incident,urgent" \
  --body "Secret exposed at commit XXXXX. Rotating immediately."

# 2. Rotate the exposed secret IMMEDIATELY
# → Follow [Manual Rotation](#rotation-procedures)

# 3. Rewrite Git history to remove secret
# Use BFG Repo-Cleaner (safest approach):
bfg --delete-files /path/to/secret-file.json

# OR git filter-branch:
git filter-branch --force --index-filter \
  'git rm -r --cached -f /path/to/secret-file.json' \
  --prune-empty --tag-name-filter cat -- --all

# 4. Force push (if you have rights)
git push origin main --force-with-lease

# 5. Verify secret is removed
git log -p | grep -i "service_account" | head

# 6. Update ROTATION_LOG.md with incident details
echo "## [$(date -u +%Y-%m-%d)] SECURITY INCIDENT: Secret exposure" >> ROTATION_LOG.md
echo "Secret rotated immediately" >> ROTATION_LOG.md
```

---

## Access Control & RBAC

### Who Can Access Secrets?

| Role | Access | Justification |
|------|--------|---|
| **GitHub Workflow Bot** | ✅ All | Automated CI/CD engine |
| **Repository Admins** | ✅ Read/Write | Need to create/update secrets |
| **Security Team** | ✅ Read/Audit | Compliance & incident response |
| **Developers** | ❌ No direct access | Use secrets via workflows only |
| **External users** | ❌ No access | Zero trust |

### If You Need Different Permissions

```bash
# For READ-ONLY audit access:
gh secret list --repo kushin77/self-hosted-runner

# For WRITE access (very restricted):
# Must be added as repo admin
# Request via: #security-requests Slack channel
# Requires: 2 security team approvals + justification

# For TEMPORARY emergency access:
# Request via: #security-emergency Slack channel
# Expires after 4 hours maximum
```

---

## Emergency Response

### 🚨 Secret Was Exposed

**If exposed on GitHub (visible to public):**
1. Follow "Secret accidentally exposed in Git" → [Troubleshooting](#troubleshooting)
2. Open emergency issue with [SECURITY INCIDENT] tag
3. Rotate secret within **15 minutes** (mandatory)
4. File incident report: ROTATION_LOG.md → Incident section
5. Schedule post-mortem within 24 hours

**If exposed in logs (CI/CD output):**
1. Check which workflows saw the secret
2. Re-run those workflows with rotated secret
3. Review log retention policies (should auto-delete in 30 days)
4. Audit all commands that touched the secret

### 🚨 Secret Rotation Failed

**All rotation attempts exhausted:**
1. Page on-call engineer (Slack #on-call)
2. Open blocking issue: "ROTATION BLOCKED: <SECRET_NAME>"
3. Manual rotation: → [Rotation Procedures](#rotation-procedures)
4. If rotation still fails, escalate to security team

### 🚨 Many Secrets Invalid

**If validation workflow shows >3 secrets broken:**
1. Open emergency incident issue
2. Disable all affected workflows (add `if: false` to jobs)
3. Contact security team immediately
4. Do NOT attempt to fix without guidance

---

## Monitoring & Alerts

### Daily Validation

```bash
# Runs automatically every day at 00:00 UTC
# Workflow: .github/workflows/verify-secrets-and-diagnose.yml

# Check status
gh workflow list --repo kushin77/self-hosted-runner | grep "verify-secrets"

# View latest run
gh run list --workflow=verify-secrets-and-diagnose.yml --limit 1
```

### Rotation Reminders

- **30 days before due**: Email reminder to ops@elevatediq.com
- **14 days before due**: Slack warning in #ops-automation
- **7 days before due**: Slack critical alert + email
- **0 days (overdue)**: Auto-create blocking issue + escalate

### Audit Trail

Every secret operation is logged:

```bash
# View rotation history
cat ROTATION_LOG.md

# View all secret-related workflow runs
gh run list --status completed --json name,conclusion,createdAt | \
  jq '.[] | select(.name | contains("secret") or contains("rotation"))'

# View GitHub audit log
# → https://github.com/kushin77/self-hosted-runner/settings/audit-log
```

---

## Best Practices

✅ **DO**
- ✅ Rotate secrets on schedule (don't skip!)
- ✅ Validate new secrets before committing
- ✅ Use `jq` to inspect JSON secrets locally
- ✅ Log all rotation events
- ✅ Use GitHub CLI for faster setup
- ✅ Keep secrets in GitHub Secrets (not in code)
- ✅ Test workflows after rotating secrets
- ✅ Keep this guide updated

❌ **DON'T**
- ❌ Hardcode secrets in workflows (always use ${{ secrets.NAME }})
- ❌ Print secrets in workflow logs
- ❌ Share secrets via email or Slack
- ❌ Reuse secrets across multiple services
- ❌ Skip validation before setting secrets
- ❌ Delay rotating expired secrets
- ❌ Leave debugging logs with secrets exposed
- ❌ Store backup secrets unencrypted

---

## Frequently Asked Questions

**Q: What's the difference between GCP_SERVICE_ACCOUNT_KEY and TF_VAR_SERVICE_ACCOUNT_KEY?**
A: They must contain **identical content**. TF_VAR_ prefix is Terraform convention. Both point to the same GCP service account. Auto-sync'd on rotation.

**Q: Can I access secrets in my local development environment?**
A: No. Secrets only exist in GitHub (secure enclave). For local dev, use temporary credentials or a separate test account.

**Q: How long are GitHub Actions audit logs retained?**
A: 90 days. If you need longer, export logs regularly: `gh audit-log list > secrets-audit-$(date +%Y%m%d).json`

**Q: What happens if I accidentally leak a secret?**
A: 1) Rotate immediately (15 min max). 2) File security incident. 3) Review attackers might have used it within rotation window. 4) Check auth logs for suspicious activity.

**Q: Can I use environment variables instead of secrets?**
A: No. Env variables are visible in workflow logs. Secrets are encrypted and masked. Always use secrets for anything sensitive.

---

## Quick Links

- 📋 [SECRETS_CLASSIFICATION.yml](./SECRETS_CLASSIFICATION.yml) — Master secrets registry
- 📝 [ROTATION_LOG.md](./ROTATION_LOG.md) — All rotations logged here
- 🔧 [GitHub Secrets Settings](https://github.com/kushin77/self-hosted-runner/settings/secrets/actions)
- 📊 [Workflow Runs](https://github.com/kushin77/self-hosted-runner/actions?query=workflow%3A%22verify-secrets%22)
- 🚀 [Rotation Workflows](https://github.com/kushin77/self-hosted-runner/blob/main/.github/workflows/?query=rotation)

---

**Last Updated**: 2026-03-07  
**Maintained By**: ci-team@elevatediq.com  
**Questions?** Open an issue or ping #ops-automation on Slack
