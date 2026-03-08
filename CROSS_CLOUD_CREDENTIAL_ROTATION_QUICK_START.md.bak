# Cross-Cloud Credential Rotation - Quick Start

**Setup Time**: 15 minutes  
**Maintenance**: 5 minutes/day  

---

## ✅ Pre-Flight Checklist

Before enabling automatic rotation:

- [ ] AWS IAM User created with programmatic access
- [ ] AWS OIDC role configured (reference: issue #1346)
- [ ] GCP Service Account created with key management permissions
- [ ] GCP OIDC workload identity provider configured
- [ ] Vault AppRole created with token renewal permissions
- [ ] All GitHub secrets populated (see Configuration section)

---

## 🚀 One-Time Setup (5 Min)

### Step 1: Verify GitHub Secrets

```bash
# Check all required secrets exist
gh secret list | grep -E "AWS_|GCP_|VAULT_"

# Required output should include:
# AWS_ROLE_TO_ASSUME
# GCP_PROJECT_ID
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# GCP_WORKLOAD_IDENTITY_PROVIDER
# VAULT_ADDR
# VAULT_ROLE_ID
# VAULT_SECRET_ID
```

### Step 2: Make Scripts Executable

```bash
chmod +x scripts/automation/cross-cloud-credential-orchestrator.sh
chmod +x scripts/automation/credential-orchestration-engine.sh

# Verify
ls -la scripts/automation/cross-cloud-credential-*.sh
```

### Step 3: Enable Workflow in GitHub

```bash
# Workflow is automatically enabled when pushed
# Verify it appears in Actions tab:
gh workflow list | grep cross-cloud-credential-rotation

# If disabled, re-enable:
gh workflow enable ".github/workflows/cross-cloud-credential-rotation.yml"
```

### Step 4: Watch First Rotation (No Wait)

```bash
# View workflow run list
gh workflow view ".github/workflows/cross-cloud-credential-rotation.yml"

# Manual trigger to watch in real-time
gh workflow run cross-cloud-credential-rotation.yml -f mode=check

# Stream logs
gh run watch (run-id)
```

---

## 📅 Automatic Operation

### What Happens Daily
```
3:00 AM UTC → Workflow triggers automatically
  ├─ Authenticate to AWS (OIDC)
  ├─ Authenticate to GCP (OIDC)
  ├─ Execute orchestration engine
  │   ├─ Check AWS key age
  │   ├─ Check Vault token age
  │   ├─ Check GCP key age
  │   └─ Rotate if needed
  ├─ Validate all credentials
  ├─ Generate compliance report
  └─ Post status to issue #1381
     
Update check → Issue #1381 shows:
  ✅ AWS: Key age 0 days
  ✅ Vault: Token age 0 hours
  ✅ GCP: Key age 0 days
  Status: ALL CURRENT
```

### Manual Triggers (If Needed)

**Check Credential Ages** (No rotation):
```bash
gh workflow run cross-cloud-credential-rotation.yml -f mode=check
```

**Execute Rotation** (Force rotation):
```bash
gh workflow run cross-cloud-credential-rotation.yml -f mode=rotate
```

**Emergency Rotation** (All clouds immediately):
```bash
gh workflow run cross-cloud-credential-rotation.yml -f mode=emergency
```

---

## 📊 Daily Monitoring (2 Min)

### Check Status
1. Navigate to: Issues → #1381
2. Scroll to latest comment (auto-updated daily)
3. Verify: All services show ✅ and status shows "CURRENT"

### View Full Logs
```bash
# Get latest run
gh run list --workflow=cross-cloud-credential-rotation.yml --limit=1

# View full logs
gh run view (run-id) --log
```

### Spot Check Credentials
```bash
# AWS
aws sts get-caller-identity

# GCP
gcloud auth list

# Vault
vault token lookup
```

---

## 🔍 Troubleshooting

### Issue: Workflow fails immediately

**Diagnosis**:
```bash
# Check workflow logs
gh run view --log | tail -50

# Test each cloud manually
aws sts get-caller-identity  # AWS
gcloud auth list             # GCP
vault status                 # Vault
```

**Fix**:
- Verify GitHub secrets: `gh secret list`
- Verify IAM permissions in each cloud
- Check OIDC provider configuration
- Run workflow again: `gh workflow run cross-cloud-credential-rotation.yml`

### Issue: Rotation fails for specific cloud

**Diagnosis**:
```bash
# Check logs for cloud-specific error
gh run view --log | grep -i "aws\|gcp\|vault"
```

**Fix for AWS**:
- Verify `AWS_ROLE_TO_ASSUME` exists and is accessible
- Check IAM permissions: iam:CreateAccessKey, iam:DeleteAccessKey

**Fix for GCP**:
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
**Fix for Vault**:
- Verify AppRole credentials: `gh secret get VAULT_ROLE_ID`
- Check: `vault list auth/approle/role`
- Manually test: `vault write -field=token auth/approle/login role_id=... secret_id=...`

### Issue: Credentials too old (not rotating)

**Check**:
```bash
# View rotation status in issue #1381
gh issue view 1381 | tail -20

# Check credential ages
gh run view --log | grep "days\|hours\|Age:"
```

**Force Rotation**:
```bash
# Trigger manual rotation
gh workflow run cross-cloud-credential-rotation.yml -f mode=rotate

# Watch progress
gh run list --workflow=cross-cloud-credential-rotation.yml --limit=1
gh run view (run-id) --log
```

---

## ⚙️ Configuration Details

### GitHub Secrets Setup

**AWS**:
```bash
# Create IAM user for rotation (one-time)
aws iam create-user --user-name github-rotation
aws iam attach-user-policy --user-name github-rotation \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# (Or least-privilege policy with iam:CreateAccessKey, iam:DeleteAccessKey)

# Create access key
aws iam create-access-key --user-name github-rotation

# Result gives AccessKeyId + SecretAccessKey
gh secret set AWS_ROTATION_ACCESS_KEY_ID --body "AKIA..."
gh secret set AWS_ROTATION_SECRET_ACCESS_KEY --body "..."

# Also set role to assume
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::ACCOUNT:role/github-orchestration"
```

**GCP**:
```bash
# Verify service account has servicemanagment.admin or editor role
gcloud iam service-accounts list

# Set secrets
gh secret set GCP_PROJECT_ID --body "my-project"
gh secret set GCP_SERVICE_ACCOUNT_EMAIL --body "rotation@project.iam.gserviceaccount.com"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/gh-pool/providers/github"
```

**Vault**:
```bash
# Create AppRole for rotation
vault write auth/approle/role/github-rotation \
  token_ttl=1h \
  token_max_ttl=4h

# Generate RoleID
vault read auth/approle/role/github-rotation/role-id

# Generate SecretID
vault write -f auth/approle/role/github-rotation/secret-id

# Set secrets
gh secret set VAULT_ADDR --body "https://vault.example.com"
gh secret set VAULT_ROLE_ID --body "..."
gh secret set VAULT_SECRET_ID --body "..."
```

### Slack Notifications (Optional)

```bash
# Create incoming webhook: https://api.slack.com/apps
# Point to your Slack workspace

# Store webhook
gh secret set SLACK_WEBHOOK_ROTATION --body "https://hooks.slack.com/services/..."

# Notifications auto-send on failures
```

---

## 📈 Monitoring & Metrics

### Key Metrics
- **Rotation Frequency**: Daily (3 AM UTC)
- **Typical Duration**: 5-10 minutes
- **Success Rate Target**: 99%+
- **Age of Credentials**: Always 0 days (immediately rotated)

### Dashboard

**Issue #1381** (Auto-Updated):
```markdown
## Rotation Status

| Cloud    | Key Age    | Max Age | Status | Last Rotated |
|----------|------------|---------|--------|--------------|
| AWS      | 0 days     | 90 days | ✅     | Today 3 AM   |
| Vault    | 0 hours    | 168 hrs | ✅     | Today 3 AM   |
| GCP      | 0 days     | 30 days | ✅     | Today 3 AM   |

**Overall**: ✅ ALL CREDENTIALS CURRENT

Next Rotation: 2026-03-09T03:00:00Z
```

---

## 🎯 Next Steps

1. **Verify Setup** (Run once):
   ```bash
   gh workflow run cross-cloud-credential-rotation.yml -f mode=check
   ```

2. **Monitor for 24 Hours**:
   - Check issue #1381 after first scheduled run
   - Verify all clouds show ✅ status

3. **Enable Slack Alerts** (Optional):
   - Create Slack incoming webhook
   - Set GitHub secret: `SLACK_WEBHOOK_ROTATION`

4. **Document in Runbook**:
   - Share manual trigger commands with ops team
   - Include troubleshooting section

---

## 📞 Support

**Questions?**
- Check logs: `gh run view --log`
- View issue: `gh issue view 1381`
- Manual test: Run workflow in check mode

**Escalation**:
- If all rotations fail → Trigger `mode=emergency`
- If specific cloud fails → Reference troubleshooting section
- Create incident issue → Will auto-trigger fallback procedures

---

**Revision**: 1.0  
**Last Updated**: March 8, 2026  
**Status**: 🟢 Ready for Production
