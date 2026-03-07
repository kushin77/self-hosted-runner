# Automation Secrets Setup Guide

**Date**: March 7, 2026  
**Status**: 🔐 All secrets can be configured now

---

## Overview

The hands-off automation system requires two secrets:

| Secret | Type | Scope | Rotation | Purpose |
|--------|------|-------|----------|---------|
| `DEPLOY_SSH_KEY` | SSH Private Key | Repo | 90 days | Ansible SSH access to runner hosts |
| `RUNNER_MGMT_TOKEN` | GitHub PAT | Repo | 90 days | GitHub API access for runner management |

---

## Quick Start (5 minutes)

### Prerequisites
- GitHub CLI installed: `gh --version`
- Authenticated with GitHub: `gh auth login`
- Repository access: `kushin77/self-hosted-runner`

### Step 1: Generate SSH Key & Set DEPLOY_SSH_KEY

```bash
chmod +x scripts/setup-automation-secrets-direct.sh
bash scripts/setup-automation-secrets-direct.sh
```

This will:
1. ✓ Generate ED25519 SSH keypair
2. ✓ Set `DEPLOY_SSH_KEY` in GitHub Secrets
3. 📋 Display public key for runner hosts
4. ⏳ Prompt for `RUNNER_MGMT_TOKEN` setup

### Step 2: Create RUNNER_MGMT_TOKEN

**Option A: GitHub Web UI (Recommended)**

1. Go to: https://github.com/settings/tokens/new
2. Fill in:
   - **Token name**: `runner-management-automation-2026-03`
   - **Expiration**: 90 days
   - **Scopes** (required):
     - ✓ `repo` (full control of private repositories)
     - ✓ `admin:repo_hook` (full control of repository hooks)
     - ✓ `admin:org_hook` (full control of organization hooks)
3. Click "Generate token"
4. Copy token immediately (won't display again)

**Option B: GitHub CLI (if you have PAT scopes)**

```bash
# Manual approach (you still need to create token in UI)
gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "$YOUR_PAT_HERE"
```

### Step 3: Verify Both Secrets

```bash
gh secret list --repo kushin77/self-hosted-runner
```

Expected output:
```
DEPLOY_SSH_KEY          Updated 2026-03-07
RUNNER_MGMT_TOKEN       Updated 2026-03-07
```

---

## Detailed Setup - DEPLOY_SSH_KEY

### What It Is
ED25519 SSH private key for authenticating Ansible to runner hosts.

### How It's Used
- `runner-self-heal.yml` → Ansible playbook → SSH to runner host
- `deploy-rotation-staging.yml` → Deploy updates via Ansible

### Generation Process

```bash
ssh-keygen -t ed25519 \
  -C "runner-deploy-automation" \
  -f ~/.ssh/runner_deploy_key \
  -N ""  # No passphrase (GitHub can't handle interactive prompts)
```

### Public Key Installation on Runner Hosts

After `DEPLOY_SSH_KEY` is set in GitHub, add the public key to each runner host:

```bash
# Option 1: Manually copy public key
echo "SSH_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Option 2: Script deployment
cat > add-deploy-key.sh << 'EOF'
#!/bin/bash
mkdir -p ~/.ssh
echo "SSH_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
EOF
bash add-deploy-key.sh
```

### Rotation Schedule
- Generate new key every 90 days
- Update GitHub Secret
- Update runner host authorized_keys
- Keep `DEPLOY_SSH_KEY` secret, share ONLY public key

---

## Detailed Setup - RUNNER_MGMT_TOKEN

### What It Is
GitHub Personal Access Token (PAT) with permissions to:
- List/read runner status
- Trigger/rerun workflows
- Create issues

### Required Scopes

| Scope | Why |
|-------|-----|
| `repo` | Read/write private repos (needed for workflow reruns) |
| `admin:repo_hook` | Access repository webhooks |
| `admin:org_hook` | Access organization webhooks (if org-level) |

### Generation Steps

1. **Navigate to Token Settings**
   ```
   https://github.com/settings/tokens/new
   ```

2. **Fill Token Details**
   - Name: `runner-management-automation-2026-03`
   - Expiration: 90 days (matches secret rotation)
   - Description: "Automation for self-hosted runner health & recovery"

3. **Select Scopes**
   ```
   ✓ repo
     ├─ Full control of private repositories
     └─ Includes: read repo, write repo, admin webhooks
   
   ✓ admin:repo_hook
     └─ Full control of repository hooks
   
   ✓ admin:org_hook (optional, if org-level access needed)
     └─ Full control of organization hooks
   ```

4. **Generate & Copy**
   - Click "Generate token"
   - ⚠️ **COPY IMMEDIATELY** - won't show again
   - Don't close tab until pasted into GitHub Secrets

### Set Token in GitHub

```bash
RUNNER_MGMT_TOKEN="ghp_xxxxxxxxxxxx..."  # Your token from step above

gh secret set RUNNER_MGMT_TOKEN \
  --repo kushin77/self-hosted-runner \
  --body "$RUNNER_MGMT_TOKEN"
```

### Test Token

```bash
export GH_TOKEN="$RUNNER_MGMT_TOKEN"
gh api /repos/kushin77/self-hosted-runner/actions/runners

# Expected: JSON list of runners
```

### Rotation Schedule
- Expires automatically after 90 days
- `secret-rotation-mgmt-token.yml` workflow validates monthly
- Creates GitHub issue reminder 30 days before expiry
- Generate new token before old one expires
- Test new token before deleting old one

---

## Security Best Practices

### 1. Never Commit Secrets
```bash
# ✓ Good: Set via CLI
gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "$TOKEN"

# ✗ Bad: Commit to git
echo "ghp_xxxx" > .env
git add .env
```

### 2. Rotate Regularly
| Secret | Rotation | Method |
|--------|----------|--------|
| `DEPLOY_SSH_KEY` | 90 days | Generate new key, update authorized_keys |
| `RUNNER_MGMT_TOKEN` | 90 days | Create new PAT, update GitHub Secret |

### 3. Limit Scope
- Only use scopes needed
- `RUNNER_MGMT_TOKEN`: Repo + hooks, NOT admin:user or admin:org
- `DEPLOY_SSH_KEY`: Deploy user only, NOT root

### 4. Audit & Monitor
- Check `gh secret list` monthly
- Monitor workflow logs for secret validation
- Review runner access logs

---

## Troubleshooting

### "gh: command not found"
```bash
# Install GitHub CLI
brew install gh        # macOS
apt-get install gh     # Debian/Ubuntu
```

### "Not authenticated with GitHub"
```bash
gh auth login
# Select: GitHub.com
# Auth protocol: HTTPS
# Login with web browser
```

### "DEPLOY_SSH_KEY is not set"
```bash
# Check what's set
gh secret list --repo kushin77/self-hosted-runner

# If missing, run setup again
bash scripts/setup-automation-secrets-direct.sh
```

### "RUNNER_MGMT_TOKEN validation fails"
```bash
# Test token
export GH_TOKEN="$YOUR_TOKEN"
gh api /repos/kushin77/self-hosted-runner/actions/runners

# If 403 Forbidden: Check scopes via GitHub web UI
# If empty: Token may lack required scopes
```

### "runner-self-heal.yml fails with SSH key error"
```bash
# Verify public key on runner host
ssh -i ~/.ssh/runner_deploy_key runner-user@runner-host "test -f ~/.ssh/authorized_keys && echo 'Key installed'"

# If failed: Add public key manually
ssh runner-user@runner-host
echo "SSH_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

---

## Deployment Checklist

Before running `runner-self-heal.yml`:

- [ ] SSH keypair generated
- [ ] `DEPLOY_SSH_KEY` set in GitHub Secrets
- [ ] GitHub PAT created with correct scopes
- [ ] `RUNNER_MGMT_TOKEN` set in GitHub Secrets
- [ ] Public key added to runner hosts
- [ ] Both secrets verified: `gh secret list --repo kushin77/self-hosted-runner`
- [ ] Token tested: `gh api /repos/kushin77/self-hosted-runner/actions/runners`
- [ ] PR #1013 merged to main
- [ ] Workflows enabled in Actions tab

---

## Automated Rotation (Post-Setup)

Once both secrets are configured, rotation is automatic:

### RUNNER_MGMT_TOKEN Rotation
**When**: 1st of month at 02:00 UTC  
**Workflow**: `secret-rotation-mgmt-token.yml`  
**Actions**:
- Validates token health
- Creates issue reminder if rotation needed
- No downtime (old token remains valid)

### DEPLOY_SSH_KEY Rotation
**When**: Every 90 days (manual)  
**Steps**:
1. Generate new SSH keypair
2. Update `DEPLOY_SSH_KEY` in GitHub
3. Update public key on runner hosts
4. Test with: `bash scripts/runner/runner-diagnostics.sh`

---

## Quick Commands Reference

```bash
# View all secrets
gh secret list --repo kushin77/self-hosted-runner

# Set a secret
gh secret set SECRET_NAME --repo kushin77/self-hosted-runner --body "$VALUE"

# Remove a secret
gh secret delete SECRET_NAME --repo kushin77/self-hosted-runner

# Test RUNNER_MGMT_TOKEN
export GH_TOKEN="$RUNNER_MGMT_TOKEN"
gh api /repos/kushin77/self-hosted-runner/actions/runners

# Generate SSH key
ssh-keygen -t ed25519 -C "deployment" -f key.pem -N ""

# Add public key to authorized_keys
cat key.pem.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## Support & Escalation

### Workflow Logs
All automation runs are logged in GitHub Actions:
```
Repository → Actions → [workflow-name] → [latest run] → Logs
```

### Failed Secret Validation
Check `secret-rotation-mgmt-token.yml` logs:
```bash
gh run list --workflow secret-rotation-mgmt-token.yml --repo kushin77/self-hosted-runner --limit 5
gh run view <RUN_ID> --repo kushin77/self-hosted-runner --log
```

### SSH Authentication Issues
Debug Ansible connection:
```bash
ansible-playbook -i ansible/inventory/staging \
  ansible/playbooks/provision-self-hosted-runner-noninteractive.yml \
  --verbose --check
```

---

**Status**: Ready for Production  
**Last Updated**: March 7, 2026  
**Next Review**: April 7, 2026 (30 days before PAT expiry)
