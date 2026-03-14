# 🔧 ENFORCEMENT TROUBLESHOOTING - Diagnostic & Fix Guide
**Status:** ✅ **ACTIVE** | **Date:** March 14, 2026 | **Version:** 1.0

---

## QUICK DIAGNOSE

Run this **first** if something is broken:

```bash
bash scripts/enforce/diagnose.sh

# Output will show:
# - Which enforcement rules are failing
# - Root cause
# - Suggested fix
# - Required action
```

---

## ENFORCEMENT RULE #1: Manual Infrastructure Changes

### Symptom: "Manual infrastructure changes detected"

**Cause:** Someone ran SSH commands directly instead of using git.

**Diagnosis:**
```bash
bash scripts/enforce/verify-no-manual-changes.sh -v

# Output shows:
# - Which files were modified directly
# - When modifications happened
# - Who made changes (if available)
```

**Fix:**
```bash
# Option A: Commit the changes (if intentional)
git add <modified-files>
git commit -m "ops: Update configuration via manual intervention (post-incident)"
git push origin main

# Option B: Revert the changes (if accidental)
git checkout HEAD -- <modified-files>

# Option C: Verify no more direct modifications
ssh ubuntu@192.168.168.42 "git -C /home/akushnir/self-hosted-runner status"
# Should show: nothing to commit, working tree clean
```

---

## ENFORCEMENT RULE #2: No Hardcoded Secrets

### Symptom: "Commit rejected: secrets detected"

**Cause:** You accidentally committed a secret (API key, token, password).

**Diagnosis:**
```bash
bash scripts/enforce/find-secrets.sh

# Output shows:
# - Which files contain secrets
# - What type of secret (AWS, GitHub, Vault, etc)
# - Suggested remediation
```

**Fix - Option 1: Remove the secret (Recommended)**
```bash
# Find which commit added the secret
git log -p --all -S 'aws_secret_key' | head -50

# Find the commit hash
git show <commit-hash>

# Option 1a: If secret is still in latest commit
git restore --staged <file>
# Remove the secret from the file
vi <file>
# Delete the secret, then:
git add <file>
git commit -m "Remove hardcoded secret"

# Option 1b: If secret is in history
# Use git filter-branch or BFG Repo-Cleaner:
# This is more complex - contact #engineering-security
```

**Fix - Option 2: Use enforce script**
```bash
bash scripts/enforce/remove-secrets.sh

# This will:
# 1. Find all hardcoded secrets
# 2. Remove them
# 3. Create a revert commit
# 4. Push revert to main (requires admin approval)
```

**Prevention for next time:**
```bash
# Ensure pre-commit hooks are installed
cd /home/akushnir/self-hosted-runner
pre-commit install
pre-commit run --all-files

# Test by attempting to commit a fake secret
echo 'API_KEY=sk-test-12345' >> test.txt
git add test.txt
git commit -m "test"
# Should be blocked by pre-commit hook
```

---

## ENFORCEMENT RULE #3: Immutable Audit Trail

### Symptom: "❌ Hash mismatch detected"

**Cause:** Audit trail file was modified or deleted (tampering).

**Diagnosis:**
```bash
bash scripts/ssh_service_accounts/audit_log_signer.sh verify -v

# Output shows:
# - Which line(s) have hash mismatches
# - Expected vs computed hash
# - Timestamp of issue
```

**Investigation:**
```bash
# Check file modification times
ls -la logs/credential-audit.jsonl*
stat logs/credential-audit.jsonl

# Check git history (logs should be committed)
git log --oneline logs/credential-audit.jsonl | head -5

# Look for suspicious git changes
git log -p logs/credential-audit.jsonl | grep -A2 -B2 "@@"
```

**Fix:**
```bash
# Option 1: Restore from git (if change was recent)
git checkout HEAD -- logs/credential-audit.jsonl
git checkout HEAD -- logs/credential-audit.jsonl.signatures

# Option 2: Restore from backup
if ls logs/archive/backup-*.jsonl 2>/dev/null; then
    cp logs/archive/backup-$(date +%Y-%m-%d).jsonl logs/credential-audit.jsonl
    bash scripts/ssh_service_accounts/audit_log_signer.sh init
fi

# Option 3: If no backup available - Incident Required
bash scripts/enforce/create-incident.sh \
  --title "Audit trail tampering detected" \
  --severity critical \
  --investigation-needed
```

**Prevention:**
```bash
# Enable file immutability on audit logs
sudo chattr +a logs/credential-audit.jsonl
sudo chattr +a logs/credential-audit.jsonl.signatures

# Verify immutability
lsattr logs/credential-audit.jsonl*
# Output should show: ----a- logs/credential-audit.jsonl

# To undo (admin only):
sudo chattr -a logs/credential-audit.jsonl
```

---

## ENFORCEMENT RULE #4: Preflight Health Gating

### Symptom: "Deployment blocked: preflight check failed"

**Cause:** Infrastructure is not ready for deployment.

**Diagnosis:**
```bash
bash scripts/ssh_service_accounts/preflight_health_gate.sh -v

# Output shows exactly which check failed:
# - ✓ (passing)
# - ! (warning, not blocking)
# - ✗ (failure, blocks deployment)
```

**Common Fixes:**

**Problem: gcloud command not found**
```bash
# Install gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# Then verify:
gcloud auth list
gcloud secrets list --project=nexusshield-prod
```

**Problem: Target unreachable (192.168.168.42)**
```bash
# Test connectivity
ping -c 3 192.168.168.42
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.168.42 "echo 'Connected'"

# If SSH fails:
# 1. Check SSH key permissions
ls -la ~/.ssh/id_ed25519
# Should be 600

# 2. Check SSH key is loaded
ssh-add -l | grep id_ed25519
# If not loaded:
ssh-add ~/.ssh/id_ed25519

# 3. Check network connectivity
# - Are you on VPN?
# - Do you have network access?
# - Is the target IP correct?
```

**Problem: Systemd timer not active**
```bash
# Check timer status
systemctl list-timers | grep credential

# If not active, start it:
systemctl start credential-rotation.timer
systemctl start ssh-health-checks.timer

# Enable for automatic start:
systemctl enable credential-rotation.timer
systemctl enable ssh-health-checks.timer

# Verify
systemctl status credential-rotation.timer
```

**Problem: Disk space low**
```bash
# Check available space
df -h /home/akushnir/self-hosted-runner

# If <500MB available, clean up old logs
bash scripts/enforce/cleanup-old-logs.sh

# Or manually:
rm -rf logs/health-checks/*.old
find logs/ -mtime +7 -delete
```

**Problem: GCP Secret Manager unreachable**
```bash
# Verify GCP authentication
gcloud auth list
gcloud config get-value project

# Try to list secrets
gcloud secrets list --project=nexusshield-prod

# If fails, re-authenticate:
gcloud auth application-default login

# Or set credentials:
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

**Auto-Fix (when possible):**
```bash
# Some issues can be automatically fixed
bash scripts/ssh_service_accounts/preflight_health_gate.sh --fix-minor

# This will:
# - Fix SSH key permissions (600)
# - Enable systemd services
# - Increase log rotation aggressiveness
# - NOT change critical infrastructure
```

---

## ENFORCEMENT RULE #5: Zero-Trust Credential Access

### Symptom: "Credential fetch failed from all layers"

**Cause:** No credential backend is accessible or secret doesn't exist.

**Diagnosis:**
```bash
bash scripts/enforce/diagnose-credentials.sh

# Output shows:
# - Which backends are available (Vault, GSM, KMS, Local)
# - Which secrets exist
# - Why fetch failed
```

**Fix by Layer:**

**Layer 1: Vault (if available)**
```bash
# Check Vault status
vault status

# If not running:
vault server -config /etc/vault/config.hcl &

# Login:
vault login -method=ldap username=<your-username>

# Verify secret exists:
vault kv list secret/ssh
vault kv get secret/ssh/<account>/private_key
```

**Layer 2: GCP Secret Manager**
```bash
# First, check credentials
gcloud auth list
gcloud config get-value project

# List available secrets
gcloud secrets list --project=nexusshield-prod

# If SSH secret missing, create it:
echo "-----BEGIN OPENSSH PRIVATE KEY-----" | \
  gcloud secrets create ssh-account-name-privatekey \
  --replication-policy="automatic" \
  --data-file=- \
  --project=nexusshield-prod
```

**Layer 3: KMS (for encryption)**
```bash
# Check KMS key exists
gcloud kms keys list \
  --location us-central1 \
  --keyring nexus-keys \
  --project nexusshield-prod

# If key missing, create it:
gcloud kms keys create ssh-key-encryption \
  --location us-central1 \
  --keyring nexus-keys \
  --purpose encryption \
  --project nexusshield-prod
```

**Layer 4: Local Backup**
```bash
# Check backup files exist and are recent
ls -la secrets/ssh/*/.*.backup

# If missing or old:
# 1. Get credential from Layer 1-3
pk=$(fetch_credential "$account" "private_key") || exit 1

# 2. Create backup
mkdir -p "secrets/ssh/$account"
echo "$pk" > "secrets/ssh/$account/.private_key.backup"
chmod 600 "secrets/ssh/$account/.private_key.backup"
```

---

## COMPLETE DIAGNOSTIC WORKFLOW

When something fails, run this complete diagnostic:

```bash
#!/bin/bash
# Complete Diagnostic Script

echo "=== ENFORCEMENT RULE #1: Manual Changes ==="
bash scripts/enforce/verify-no-manual-changes.sh && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "=== ENFORCEMENT RULE #2: No Secrets ==="
bash scripts/enforce/find-secrets.sh && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "=== ENFORCEMENT RULE #3: Audit Trail ==="
bash scripts/ssh_service_accounts/audit_log_signer.sh verify && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "=== ENFORCEMENT RULE #4: Health Gating ==="
bash scripts/ssh_service_accounts/preflight_health_gate.sh && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "=== ENFORCEMENT RULE #5: Credentials ==="
bash scripts/enforce/diagnose-credentials.sh && echo "✓ PASS" || echo "✗ FAIL"

echo ""
echo "=== SYSTEM STATUS ==="
systemctl status service-account-credential-rotation.service | head -5
systemctl list-timers | grep credential | head -3
df -h /home/akushnir/self-hosted-runner | tail -1

echo ""
echo "=== NEXT STEPS ==="
echo "If all rules are ✓ PASS, system is healthy"
echo "If any are ✗ FAIL, use this guide for specific fixes"
```

---

## INCIDENT CREATION

If a problem can't be auto-fixed, create an incident:

```bash
bash scripts/enforce/create-incident.sh \
  --title "Enforcement Rule #X failed" \
  --severity high \
  --description "Describe what failed" \
  --rule-number "3" \
  --assign-to "#engineering-oncall"

# This will:
# - Create a GitHub issue
# - Notify the on-call team
# - Add to incident dashboard
# - Log to audit trail
```

---

## ESCALATION PATH

| Problem | Who Can Fix | Escalation |
|---------|------------|------------|
| SSH key permission issues | Developer | None |
| GCP authentication | DevOps team | Engineering lead |
| Audit trail tampering | Security team | Chief Security Officer |
| Critical hardware failure | Infrastructure | Executive on-call |

---

## SUPPORT

- **Slack:** #engineering-deployments
- **On-call:** #engineering-oncall (for emergencies)
- **Issues:** Tag with `enforcement:` label
- **Documentation:** See [ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md)

