# SECRETS SETUP - COMPLETE PACKAGE

**Status**: 🎯 READY FOR IMMEDIATE DEPLOYMENT  
**Date**: March 7, 2026  
**Package Version**: 1.0-production

---

## What's Included

### 📦 Setup Scripts

1. **`scripts/setup-automation-secrets-direct.sh`** (RECOMMENDED)
   - Fastest way to set up secrets
   - Generates SSH keys
   - Sets `DEPLOY_SSH_KEY` in GitHub
   - Provides public key for runner hosts
   - Prompts for `RUNNER_MGMT_TOKEN`

   **Usage:**
   ```bash
   bash scripts/setup-automation-secrets-direct.sh
   ```

2. **`scripts/setup-automation-secrets.sh`** (COMPREHENSIVE)
   - Detailed step-by-step setup
   - Includes host preparation steps
   - More verbose logging
   - Good for first-time setup

   **Usage:**
   ```bash
   bash scripts/setup-automation-secrets.sh kushin77/self-hosted-runner
   ```

---

### 📚 Documentation Files

1. **`SECRETS_SETUP_GUIDE.md`** (THIS DOCUMENT'S SISTER)
   - Complete reference guide
   - Security best practices
   - Troubleshooting section
   - Command reference

2. **`AUTOMATION_DEPLOYMENT_CHECKLIST.md`**
   - Step-by-step deployment instructions
   - Pre-deployment verification
   - Success criteria
   - Post-deployment monitoring

3. **`AUTOMATION_DELIVERY_COMPLETE.md`**
   - Architecture overview
   - Operations procedures
   - Monitoring & observability
   - Security & compliance

---

## 🚀 START HERE: 5-Minute Setup

### Prerequisites Check

```bash
# Verify requirements
which gh        # GitHub CLI installed?
gh auth status  # Authenticated with GitHub?
which ssh-keygen # SSH tools available?
```

If any fail:
- Install GitHub CLI: `apt-get install gh`
- Install ssh tools: `apt-get install openssh-client`
- Authenticate: `gh auth login`

### Step 1: Run Secret Setup (1 minute)

```bash
cd /home/akushnir/self-hosted-runner
bash scripts/setup-automation-secrets-direct.sh
```

**Output**: 
- ✅ SSH keypair generated
- ✅ `DEPLOY_SSH_KEY` stored in GitHub
- 📋 Public key displayed for runner hosts

### Step 2: Create GitHub PAT (3 minutes)

Go to: https://github.com/settings/tokens/new

**Checklist:**
- [ ] Name: `runner-management-automation-2026-03`
- [ ] Expiration: 90 days
- [ ] Scope: ✓ repo
- [ ] Scope: ✓ admin:repo_hook
- [ ] Scope: ✓ admin:org_hook (optional)
- [ ] Click "Generate token"
- [ ] **COPY TOKEN** (won't show again!)

### Step 3: Set RUNNER_MGMT_TOKEN (1 minute)

```bash
gh secret set RUNNER_MGMT_TOKEN \
  --repo kushin77/self-hosted-runner \
  --body "ghp_YOUR_TOKEN_HERE"
```

### Step 4: Verify Both Secrets (Instant)

```bash
gh secret list --repo kushin77/self-hosted-runner
```

Expected:
```
DEPLOY_SSH_KEY          Updated 2026-03-07
RUNNER_MGMT_TOKEN       Updated 2026-03-07
```

### Step 5: Add Public Key to Runners (1 minute per host)

For each runner host:

```bash
# Option 1: Stdin (recommended)
echo "paste-public-key-here" | ssh runner@host 'cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

# Option 2: Manual SSH session
ssh runner@host
mkdir -p ~/.ssh
echo "public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

### ✅ DONE! Next: Deploy Automation

---

## 🔐 What Each Secret Does

### DEPLOY_SSH_KEY
- **What**: ED25519 SSH private key
- **Who Uses**: Ansible in `runner-self-heal.yml` and `deploy-rotation-staging.yml`
- **Where Stored**: GitHub Secrets (encrypted at rest)
- **Scope**: Repository only
- **Rotation**: Every 90 days

### RUNNER_MGMT_TOKEN
- **What**: GitHub Personal Access Token
- **Who Uses**: `runner-self-heal.yml`, `admin-token-watch.yml`, `secret-rotation-mgmt-token.yml`
- **Where Stored**: GitHub Secrets (encrypted at rest)
- **Scope**: Repository only
- **Grants Access To**: 
  - List runners via GitHub API
  - Trigger workflow reruns
  - Create issues

---

## 📋 Quick Command Reference

```bash
# === SETUP ===

# Generate SSH key
ssh-keygen -t ed25519 -C "runner-deploy" -f ~/.ssh/runner_key -N ""

# Set secret
gh secret set SECRET_NAME --repo kushin77/self-hosted-runner --body "$VALUE"

# === VERIFICATION ===

# List all secrets
gh secret list --repo kushin77/self-hosted-runner

# Test RUNNER_MGMT_TOKEN
export GH_TOKEN="ghp_xxx"
gh api /repos/kushin77/self-hosted-runner/actions/runners

# Test SSH key
ssh -i ~/.ssh/runner_key runner@host "echo OK"

# === DEPLOYMENT ===

# Merge PR #1013
gh pr merge 1013 --repo kushin77/self-hosted-runner --squash

# Enable workflows
gh workflow enable runner-self-heal.yml --repo kushin77/self-hosted-runner

# Trigger test run
gh workflow run runner-self-heal.yml --repo kushin77/self-hosted-runner --ref main

# === MONITORING ===

# View recent workflow runs
gh run list --repo kushin77/self-hosted-runner --limit 10

# View specific run logs
gh run view <RUN_ID> --repo kushin77/self-hosted-runner --log

# === ROTATION ===

# Update secret
gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "$NEW_TOKEN"
```

---

## ⚠️ Important Reminders

### 1. Protect Your Tokens
- Never commit secrets to git
- Don't share tokens in chat/email
- Use GitHub Secrets for storage
- Rotate every 90 days

### 2. GitHub PAT Scopes
Required minimum:
- `repo` - for workflow access
- `admin:repo_hook` - for webhook management
- `admin:org_hook` - for org-wide settings (optional)

**Never use:**
- `admin:user` (way too powerful)
- `admin:org` (full org access)

### 3. SSH Key Permissions
```bash
chmod 600 ~/.ssh/authorized_keys    # On runner hosts
chmod 700 ~/.ssh                     # On runner hosts
```

### 4. Backup Strategy
- [ ] Save `DEPLOY_SSH_KEY` to secure backup location
- [ ] Save `RUNNER_MGMT_TOKEN` securely (password manager)
- [ ] Document rotation dates
- [ ] Set calendar reminders for 90-day rotation

---

## 🔄 Rotation Schedule

### DEPLOY_SSH_KEY Rotation
**When**: Every 90 days  
**Who**: DevOps/Admin team  
**Steps**:
1. Generate new SSH keypair
2. Update `DEPLOY_SSH_KEY` in GitHub Secrets
3. Update public key on all runner hosts
4. Test with: `ssh -i new_key runner@host echo OK`
5. Delete old key from all hosts

### RUNNER_MGMT_TOKEN Rotation
**When**: Every 90 days (automated reminder)  
**Who**: Triggered by `secret-rotation-mgmt-token.yml`  
**Steps**:
1. Workflow validates token monthly
2. Creates GitHub issue 30 days before expiry
3. Manual: Generate new PAT at https://github.com/settings/tokens
4. Manual: Update `RUNNER_MGMT_TOKEN` with new value
5. Keep old token for 1 day during transition

---

## 🎯 Final Deployment Steps

After secrets are set:

1. **Merge PR #1013**
   ```bash
   gh pr merge 1013 --repo kushin77/self-hosted-runner --squash
   ```

2. **Verify Workflows Active**
   ```bash
   gh workflow list --repo kushin77/self-hosted-runner
   ```
   Expected:
   ```
   runner-self-heal                    active
   admin-token-watch                   active
   secret-rotation-mgmt-token          active
   ```

3. **Monitor 24 Hours**
   - Check Actions tab every hour
   - Review logs for errors
   - Verify no 403/401 auth failures

4. **Success Criteria**
   - ✅ `runner-self-heal.yml` runs every 5 min
   - ✅ All runs succeed (green checkmarks)
   - ✅ No auth/permission errors
   - ✅ Ephemeral cleanup confirmed in logs

---

## 🚨 Emergency Procedures

### Runner Offline, Auto-Heal Not Working

```bash
# 1. Check workflow logs
gh run list --workflow runner-self-heal.yml --repo kushin77/self-hosted-runner --limit 1
gh run view <RUN_ID> --repo kushin77/self-hosted-runner --log

# 2. Manual trigger
gh workflow run runner-self-heal.yml --repo kushin77/self-hosted-runner --ref main

# 3. Manual restart (if needed)
ssh -i ~/.ssh/runner_key runner@host "sudo systemctl restart actions.runner"
```

### Secret Not Working

```bash
# 1. Verify secret is set
gh secret list --repo kushin77/self-hosted-runner

# 2. Check token validity (for RUNNER_MGMT_TOKEN)
export GH_TOKEN="$YOUR_TOKEN"
gh api /repos/kushin77/self-hosted-runner/actions/runners

# 3. Update secret if needed
gh secret set SECRET_NAME --repo kushin77/self-hosted-runner --body "$NEW_VALUE"

# 4. Trigger test workflow
gh workflow run runner-self-heal.yml --repo kushin77/self-hosted-runner --ref main
```

---

## 📞 Support

**Documentation Files:**
- Setup Guide: `SECRETS_SETUP_GUIDE.md`
- Deployment Checklist: `AUTOMATION_DEPLOYMENT_CHECKLIST.md`
- Architecture: `AUTOMATION_DELIVERY_COMPLETE.md`
- Operations: `AUTOMATION_RUNBOOK.md`

**Scripts:**
- Quick Setup: `scripts/setup-automation-secrets-direct.sh`
- Detailed Setup: `scripts/setup-automation-secrets.sh`
- Validation: `scripts/automation/validate-idempotency.sh`

**Workflows:**
- Health Check: `.github/workflows/runner-self-heal.yml`
- Failure Watch: `.github/workflows/admin-token-watch.yml`
- Secret Rotation: `.github/workflows/secret-rotation-mgmt-token.yml`

---

**Status**: ✅ READY FOR PRODUCTION  
**Last Updated**: March 7, 2026  
**Next Action**: Run setup scripts and merge PR #1013
