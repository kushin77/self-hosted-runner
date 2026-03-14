# 📋 DEPLOYMENT INSTRUCTIONS - Complete Procedures
**Status:** ✅ **OPERATIONAL** | **Last Updated:** March 14, 2026 | **Audience:** Developers, DevOps, Operations

---

## TABLE OF CONTENTS

1. [Prerequisites](#prerequisites)
2. [Development Workflow](#development-workflow)
3. [Pre-Deployment Checklist](#pre-deployment-checklist)
4. [Deployment Process](#deployment-process)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)

---

## PREREQUISITES

### Required Tools
```bash
# Verify all tools installed and accessible
bash scripts/enforce/check-prerequisites.sh

# Expected output:
# ✓ git version 2.40+
# ✓ ssh-keygen (OpenSSH_9.0+)
# ✓ gcloud (version 450+)
# ✓ jq (version 1.6+)
# ✓ curl (version 7.68+)
# ✓ bash (version 5.0+)
```

### Repository Access
```bash
# SSH access to GitHub with key authentication
ssh -T git@github.com
# Expected: "Hi kushin77! You've successfully authenticated, but GitHub does not provide shell access."

# Git configuration verification 
git config user.email
git config user.name
# Both should be set and reflect your identity
```

### Cloud Access
```bash
# GCP Secret Manager access
gcloud secrets list --project=nexusshield-prod
# Should list 15+ SSH secrets without errors

# GCP authentication status
gcloud auth list
# Should show authenticated user

# Default GCP project
gcloud config get-value project
# Should return: nexusshield-prod
```

### Target Infrastructure
```bash
# Verify production target is reachable
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.42 "echo 'Connected'"
# Expected: "Connected"

# Verify backup target is reachable
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.39 "echo 'Backup OK'"
# Expected: "Backup OK"
```

---

## DEVELOPMENT WORKFLOW

### Step 1: Create Feature Branch

```bash
# Start from main (always)
git checkout main
git pull origin main

# Create feature branch with naming convention
git checkout -b feature/my-feature-name
# OR
git checkout -b fix/issue-123
# OR  
git checkout -b docs/update-readme
```

### Naming Convention
- `feature/*` - New features
- `fix/*` - Bug fixes
- `docs/*` - Documentation updates
- `refactor/*` - Code refactoring
- `test/*` - Test additions
- `chore/*` - Maintenance tasks

### Step 2: Make Changes

```bash
# Edit your files
vi path/to/file.ts

# Stage changes
git add path/to/file.ts

# Pre-commit hooks will automatically run:
# - Secrets scanning (fail if secrets found)
# - Lint checking (warn if style issues)
# - Format checking (auto-fix formatting)
# - Git commit signing

# Commit with clear message
git commit -m "feat: Add new authentication feature

- Implemented OAuth2 provider integration
- Added refresh token rotation
- Updated audit logging

Fixes #123
"
```

### Commit Message Format
```
<type>(<scope>): <subject>

<body>

<footer>

Type: feat|fix|docs|style|refactor|test|chore
Scope: area affected (optional)
Subject: what was changed (present tense)
Body: why it was changed (can be multi-line)
Footer: issue references (fixes #123)
```

### Step 3: Run Local Tests

```bash
# Pre-deployment validation
bash scripts/enforce/verify-no-manual-changes.sh
bash scripts/ssh_service_accounts/preflight_health_gate.sh
bash scripts/enforce/check-prerequisites.sh

# All should output: ✅ PASSED
```

### Step 4: Push and Create Pull Request

```bash
# Push to remote
git push origin feature/my-feature-name

# Create PR via GitHub UI or CLI
gh pr create \
  --title "Add new authentication feature" \
  --body "Implements OAuth2 provider integration with refresh token rotation" \
  --base main

# PR requirements (automated):
# - ✓ 1+ review approval required
# - ✓ Pre-commit hooks passing (no secrets)
# - ✓ Cloud Build job succeeding
# - ✓ All status checks passing
```

---

## PRE-DEPLOYMENT CHECKLIST

Run this **before every deployment**:

```bash
#!/bin/bash
# Pre-Deployment Validation Script

echo "🔍 Running pre-deployment checks..."

# 1. Enforce Rule #1: No Manual Changes
echo "1️⃣  Checking for manual infrastructure changes..."
bash scripts/enforce/verify-no-manual-changes.sh || exit 1

# 2. Enforce Rule #2: No Hardcoded Secrets
echo "2️⃣  Scanning for hardcoded secrets..."
bash scripts/enforce/verify-no-secrets.sh || exit 1

# 3. Verify git status
echo "3️⃣  Verifying git status..."
[[ $(git status --porcelain) == "" ]] || {
    echo "❌ Uncommitted changes detected"
    git status
    exit 1
}

# 4. Enforce Rule #4: Health Gating
echo "4️⃣  Running preflight health gate..."
bash scripts/ssh_service_accounts/preflight_health_gate.sh || exit 1

# 5. Verify connectivity to targets
echo "5️⃣  Verifying target connectivity..."
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.42 "echo '✓ Production target reachable'"
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.39 "echo '✓ Backup target reachable'"

# 6. Verify audit trail
echo "6️⃣  Verifying audit trail integrity..."
bash scripts/enforce/verify-audit-trail-integrity.sh || exit 1

echo ""
echo "✅ All pre-deployment checks PASSED"
echo "Ready for deployment!"
```

---

## DEPLOYMENT PROCESS

### ⚡ MANDATE: Fresh Build Deployment

> **CRITICAL:** All deployments must use **FRESH BUILD** strategy:
> - ✅ Complete stack rebuilt from scratch
> - ✅ All previous state removed (clean slate)
> - ✅ All credentials generated fresh
> - ✅ **ON-PREM ONLY** (192.168.168.42, 192.168.168.39)
> - ❌ **NO CLOUD** deployment (GCP, AWS, Azure blocked)

### Option A: Automatic Fresh Build Deployment (Recommended)

```bash
# Simply merge to main - triggers fresh build
git checkout main
git merge feature/my-feature-name

# OR via GitHub UI: Click "Merge pull request"

# Automatic actions will trigger FRESH BUILD:
# 1. Mandate validation (on-prem only, no cloud)
# 2. Cloud environment prevention checks
# 3. Previous state removed (clean slate)
# 4. Fresh git clone of repository
# 5. Fresh service account provisioning
# 6. Fresh Ed25519 SSH key generation
# 7. Fresh component deployment from scratch
# 8. Fresh credential verification
# 9. Health checks on fresh stack (10 min)
# 10. Audit trail updated with fresh deployment marker
```

### Option B: Manual Fresh Build Deployment (Development Only)

```bash
# For testing fresh builds in development environment only
cd /home/akushnir/self-hosted-runner

# Step 1: Verify on-prem environment (MANDATE)
# Must be on-prem only, no cloud credentials
env | grep -E 'GOOGLE_APPLICATION_CREDENTIALS|AWS_|AZURE_' && \
  { echo "❌ MANDATE VIOLATION: Cloud credentials detected"; exit 1; } || \
  echo "✅ No cloud credentials - safe to proceed"

# Step 2: Verify target is on-prem (MANDATE)
# Only 192.168.168.42 (primary) or 192.168.168.39 (backup)
TARGET_HOST=192.168.168.42
echo "✅ Target: $TARGET_HOST (on-prem verified)"

# Step 3: Verify prerequisites
bash scripts/enforce/check-prerequisites.sh

# Step 4: Run pre-deployment checks
bash scripts/enforce/verify-no-manual-changes.sh
bash scripts/ssh_service_accounts/preflight_health_gate.sh

# Step 5: Begin logging
source scripts/ssh_service_accounts/change_control_tracker.sh
log_operation "deployment" "begin" "build_type=fresh,environment=dev"

# Step 6: Deploy with fresh build (removes previous state)
# This will:
#   - Remove all previous deployment state
#   - Fresh clone from git
#   - Fresh service account setup
#   - Fresh credential generation
#   - Fresh systemd service startup
TARGET_HOST=192.168.168.42 bash deploy-worker-node.sh

# Step 7: Post-deployment fresh build verification
bash scripts/enforce/verify-audit-trail-integrity.sh
bash scripts/ssh_service_accounts/health_check.sh report

# Step 8: Verify fresh state
echo "✅ Verify fresh deployment:"
ssh -i ~/.ssh/automation_ed25519 automation@192.168.168.42 \
  "ls -l /opt/automation/deployment/ | head -10"
# Should show recent timestamps (just deployed)

# Step 9: Complete logging
log_operation "deployment" "end" "status=success,build_type=fresh,environment=dev"
```

### Option C: Override to Incremental? (NOT RECOMMENDED)

> ⚠️ **WARNING:** Only use if explicitly required by operations team
> Fresh builds are the default and strongly preferred

```bash
# To deploy WITHOUT fresh build reset (keep previous state)
# This is NOT RECOMMENDED and must be approved
SKIP_FRESH_BUILD=true TARGET_HOST=192.168.168.42 bash deploy-worker-node.sh

# Note: This still enforces on-prem only and cloud prevention
# It simply skips removing previous state
```

---

## POST-DEPLOYMENT VERIFICATION

After deployment completes, verify all systems:

```bash
# 1. Check all systemd services
systemctl list-units --type=service --state=running | grep -E "credential-rotation|health-checks|audit-logger"
# Expected: 5+ services running

# 2. Check all timers
systemctl list-timers --all | grep -E "credential|health"
# Expected: 2 timers active

# 3. Health report
bash scripts/ssh_service_accounts/health_check.sh report
# Expected: All 32+ accounts ONLINE

# 4. Audit trail status
bash scripts/ssh_service_accounts/audit_log_signer.sh status
# Expected: All entries signed and verified

# 5. Rollback health (verify backups are fresh)
bash scripts/ssh_service_accounts/rotation_rollback_handler.sh quarantine
# Expected: No quarantined accounts

# 6. Git status (confirm deployment tracked)
git log --oneline -5
# Expected: Latest commit is deployment

# 7. Endpoint verification
curl -s http://192.168.168.42:5000/health | jq .
# Expected: HTTP 200 + status=healthy
```

---

## ROLLBACK PROCEDURES

### Scenario 1: Deployment Failed (Automatic)

The system automatically rolls back if:
- Health checks fail post-deployment
- Critical services don't start
- Audit trail verification fails

**What happens automatically:**
```
1. All recent systemd services stopped
2. Previous version restored from git
3. Services restarted
4. Health checks verified
5. Incident created (#incident-rollback-XXXXX)
6. Team notified via Slack
7. Logs collected automatically
```

### Scenario 2: Manual Rollback Required

```bash
# Option A: Git revert (recommended for code changes)
git log --oneline
# Find the commit to rollback
# 2b1c3a4 feat: Add new feature (bad)
# 1a2b3c4 fix: Previous fix (good)

git revert 2b1c3a4
git push origin main
# Auto-deployment will deploy previous version

# Option B: Service restart (for configuration changes)
systemctl restart service-account-credential-rotation.service
systemctl restart service-account-health-checks.service

# Option C: Full infrastructure rollback
bash scripts/enforce/rollback-to-last-known-good.sh
```

### Rollback Verification

```bash
# After rollback, verify system is healthy
bash scripts/ssh_service_accounts/health_check.sh report
# All accounts should be ONLINE

# Verify git is at correct version
git log --oneline -3
# Should show rollback commit

# Verify audit trail is accurate
bash scripts/ssh_service_accounts/audit_log_signer.sh verify
# Should show: ✓ Audit trail integrity verified

# Confirm target infrastructure is stable
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.42 "ps aux | grep credential"
# Should show rotating credential processes
```

---

## TROUBLESHOOTING

### Issue: Pre-deployment check fails

```bash
# Diagnose the problem
bash scripts/enforce/diagnose.sh

# This will show:
# - All failing checks
# - Root cause
# - Suggested fix

# Common issues:
# 1. gcloud not authenticated
#    Fix: gcloud auth application-default login

# 2. Target unreachable
#    Fix: ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.42 ls
#    If fails: check network, VPN, SSH key permissions

# 3. Secrets not in GSM
#    Fix: gcloud secrets list --project=nexusshield-prod | grep ssh
#    If missing: see ENFORCEMENT_RULES.md Rule #2

# 4. Disk full
#    Fix: bash scripts/enforce/cleanup-old-logs.sh
#    Then retry deployment
```

### Issue: Deployment blocked by secrets scanning

```bash
# Identify secret in code
bash scripts/enforce/find-secrets.sh

# Remove the secret
git log -p -S 'aws_secret_key' | grep -A5 -B5 'aws_secret_key'
git revert <commit-with-secret>

# Or use automated cleanup
bash scripts/enforce/remove-secrets.sh
```

### Issue: Health check failing post-deployment

```bash
# Get health status
curl -s http://192.168.168.42:5000/health | jq .

# Check systemd status
systemctl status service-account-health-checks.service
journalctl -u service-account-health-checks.service -n 50

# Run health check manually
bash scripts/ssh_service_accounts/health_check.sh report -v

# If SSH connectivity failing:
ssh -vvv -i ~/.ssh/id_ed25519 ubuntu@192.168.168.42 "whoami"
# Review -vvv output for authentication issues
```

### Issue: Rollback wasn't automatic, need manual intervention

```bash
# Step 1: Stop current deployment
systemctl stop service-account-credential-rotation.service

# Step 2: Check git for last known good
git log --oneline | head -10
# Identify last working commit

# Step 3: Rollback
git reset --hard <commit-sha>

# Step 4: Restart services
systemctl start service-account-credential-rotation.service
systemctl start service-account-health-checks.service

# Step 5: Verify
bash scripts/ssh_service_accounts/health_check.sh report

# Step 6: Update incident
bash scripts/enforce/create-incident.sh \
  --title "Manual rollback executed" \
  --severity critical \
  --tags rollback,manual-intervention
```

---

## GETTING HELP

| Issue | Resource |
|-------|----------|
| **Deployment Questions** | See this file + [ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md) |
| **Code Level Mandates** | See [CODE_MANDATES.md](CODE_MANDATES.md) |
| **Infrastructure Issues** | See [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) |
| **Emergency/Pages** | Slack #engineering-oncall |
| **General Questions** | Slack #engineering-deployments |

---

## SUMMARY

✅ **Read this guide before first deployment**  
✅ **Follow the pre-deployment checklist every time**  
✅ **Enforce Rule #4 (Health Gating) stops bad deployments**  
✅ **Audit trail tracks everything (Rule #3)**  
✅ **Rollback is automatic - systems are designed to fail safely**  

**Happy deploying! 🚀**
