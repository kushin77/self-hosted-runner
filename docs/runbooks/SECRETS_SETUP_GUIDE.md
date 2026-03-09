# Automation Secrets Setup Guide

**Date**: March 7, 2026  
**Status**: 🔐 All secrets can be configured now

---

## Overview

The hands-off automation system requires core secrets plus optional notification secrets:

| Secret | Type | Scope | Rotation | Purpose | Required |
|--------|------|-------|----------|---------|----------|
| `DEPLOY_SSH_KEY` | SSH Private Key | Repo | 90 days | Ansible SSH access to runner hosts | ✅ Yes |
| `RUNNER_MGMT_TOKEN` | GitHub PAT | Repo | 90 days | GitHub API access for runner management | ✅ Yes |
| `SMTP_RELAY_URL` | SMTP URL | Repo | 6 months | Email notifications (fallback if Slack unavailable) | ⭕ Optional |

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

## Detailed Setup - SMTP_RELAY_URL (Optional)

### What It Is
SMTP relay URL for sending email notifications from automation workflows.

### When You Need It
- Slack webhook is unavailable or rate-limited
- Email fallback for critical alerts required
- Compliance requires audit trail via email

### Format

The secret should be an SMTP URL:

```
smtp://username:password@host:port
smtps://username:password@host:port    # For TLS
```

**Example:**
```
smtps://noreply%40company.com:AppPassword123@smtp.gmail.com:587
smtps://relay-user:relay-pass@mail.company.com:465
```

### Generation Steps

#### Option 1: Gmail App Password (Easiest)

1. **Enable 2FA on Google Account**
   - Go to: https://myaccount.google.com/security
   - Enable 2-Step Verification

2. **Create App Password**
   - Go to: https://myaccount.google.com/apppasswords
   - Select: Mail → Windows Computer (or your OS)
   - Copy generated 16-character password

3. **Format URL**
   ```
   smtps://your-email%40gmail.com:xxxxxxxxxxxxxxxx@smtp.gmail.com:587
   ```

4. **Test in GitHub**
   ```bash
   gh secret set SMTP_RELAY_URL \
     --repo kushin77/self-hosted-runner \
     --body "smtps://your-email%40gmail.com:PASSWORD@smtp.gmail.com:587"
   ```

#### Option 2: Company SMTP Relay

If your company provides SMTP relay:

1. **Get relay details from IT**
   - Host: `mail.company.com`
   - Port: `587` or `465`
   - Username/Password: Provided by IT
   - TLS required: Yes/No

2. **Format URL**
   ```
   smtps://relay-user:relay-password@mail.company.com:465
   ```

3. **URL Encode special characters**
   ```bash
   # If password has @, %, #, etc:
   python3 -c "import urllib.parse; print(urllib.parse.quote('my@password', safe=''))"
   # Output: my%40password
   ```

4. **Set in GitHub**
   ```bash
   gh secret set SMTP_RELAY_URL \
     --repo kushin77/self-hosted-runner \
     --body "smtps://user:encoded-password@mail.company.com:465"
   ```

#### Option 3: GCP Secret Manager (Enterprise)

For enterprise environments:

1. **Store in GCP Secret Manager**
   ```bash
   gcloud secrets create smtp-relay-url \
     --replication-policy="automatic" \
     --data-file=- << EOF
   smtps://relay-user:relay-pass@smtp.company.com:465
   EOF
   ```

2. **Grant GitHub Actions access**
   ```bash
   gcloud secrets add-iam-policy-binding smtp-relay-url \
     --member="serviceAccount:self-hosted-runner@PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   ```

3. **Use in workflow**
   ```yaml
   - name: Get SMTP credentials
     id: smtp
     run: |
       SMTP_URL=$(gcloud secrets versions access latest --secret=smtp-relay-url)
       echo "::add-mask::$SMTP_URL"
       echo "URL=$SMTP_URL" >> $GITHUB_OUTPUT
   
   - name: Send email notification
     run: |
       curl -X POST \
         --url "smtp://${{ steps.smtp.outputs.URL }}/send" \
         -d '{"to":"ops@company.com","subject":"Alert"}'
   ```

### Test SMTP Relay

```bash
# Option 1: Test with curl
SMTP_URL="smtps://user:pass@smtp.gmail.com:587"

# Option 2: Test with Python
python3 << 'EOF'
import smtplib
from urllib.parse import urlparse

smtp_url = "smtps://user:pass@host:port"
parsed = urlparse(smtp_url)

server = smtplib.SMTP(parsed.hostname, parsed.port)
server.starttls()
server.login(parsed.username, parsed.password)
print("✓ SMTP connection successful")
server.quit()
EOF

# Option 3: In workflow (add test step)
name: Test SMTP
on: workflow_dispatch
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Test SMTP connection
        env:
          SMTP_URL: ${{ secrets.SMTP_RELAY_URL }}
        run: |
          python3 << 'EOF'
          import smtplib
          from urllib.parse import urlparse
          parsed = urlparse("$SMTP_URL")
          smtp = smtplib.SMTP(parsed.hostname, int(parsed.port or 25))
          smtp.starttls()
          smtp.login(parsed.username, parsed.password)
          print("✓ SMTP relay is working")
          smtp.quit()
          EOF
```

### Usage in Workflows

Workflows that support SMTP_RELAY_URL:

- `security-audit.yml` — Email critical findings if Slack unavailable
- `secret-rotation-mgmt-token.yml` — Email rotation reminders
- `disaster-recovery-test.yml` — Email DR test results

Example usage:
```yaml
- name: Send email notification
  if: failure()
  env:
    SMTP_URL: ${{ secrets.SMTP_RELAY_URL }}
  run: |
    python3 << 'EOF'
    import smtplib
    from email.mime.text import MIMEText
    from urllib.parse import urlparse
    
    parsed = urlparse("${SMTP_URL}")
    smtp = smtplib.SMTP(parsed.hostname, int(parsed.port or 25))
    smtp.starttls()
    smtp.login(parsed.username, parsed.password)
    
    msg = MIMEText("Workflow failed: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}")
    msg['Subject'] = 'Automation Alert: Workflow Failed'
    msg['From'] = parsed.username
    msg['To'] = 'ops@example.com'
    
    smtp.send_message(msg)
    smtp.quit()
    print("✓ Email sent successfully")
    EOF
```

### Rotation Schedule
- Gmail App Passwords: Rotate every 6 months
- Company SMTP: Follow your organization's password policy
- Test quarterly with: `gh workflow run test-smtp-relay.yml`

### Troubleshooting SMTP

| Issue | Solution |
|-------|----------|
| `Authentication failed` | Check username/password are URL-encoded; test with Python script |
| `Connection refused` | Check host/port correct; ensure TLS port (465/587) not blocking |
| `starttls() failed` | Some servers require explicit STARTLS; try port 587 with STARTTLS |
| `Email not received` | Check sender email whitelisted; review spam folder; check recipient valid |

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
