# SSH Key-Only Authentication Implementation - Execution Guide

**Status:** 🚀 **PHASE 1 - IMMEDIATE DEPLOYMENT**  
**Start Date:** 2026-03-14  
**Target Completion:** 2026-03-15  
**Authority:** Approved with full authority to proceed

---

## Quick Start (Execute Now)

### Step 1: Deploy All 32 Service Accounts (5-10 minutes)

```bash
cd /home/akushnir/self-hosted-runner

# Make deployment script executable
chmod +x scripts/ssh_service_accounts/deploy_all_32_accounts.sh

# Execute full deployment
bash scripts/ssh_service_accounts/deploy_all_32_accounts.sh

# Monitor progress
tail -f logs/deployment/deployment-all-accounts-*.log
```

### Step 2: Enable Systemd Automation (1 minute)

```bash
# Copy systemd service files
sudo cp services/systemd/service-account-*.service /etc/systemd/system/
sudo cp services/systemd/service-account-*.timer /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
sudo systemctl enable service-account-health-check.timer
sudo systemctl start service-account-health-check.timer

sudo systemctl enable service-account-credential-rotation.timer
sudo systemctl start service-account-credential-rotation.timer

# Verify timers running
sudo systemctl status service-account-health-check.timer
sudo systemctl status service-account-credential-rotation.timer
```

### Step 3: Verify Deployment (2 minutes)

```bash
# Check health status
bash scripts/ssh_service_accounts/health_check.sh report

# View audit trail
tail -20 logs/audit-trail.jsonl

# Test a service account directly
ssh -o BatchMode=yes \
    -i ~/.ssh/svc-keys/nexus-api-runner_key \
    nexus-api-runner@192.168.168.42 whoami

# Check systemd logs
sudo journalctl -u service-account-health-check.service -n 20
```

---

## Deployment Overview

### What Gets Deployed

**32 Service Accounts Across 5 Categories:**

```
Infrastructure (7)
├─ nexus-deploy-automation
├─ nexus-k8s-operator
├─ nexus-terraform-runner
├─ nexus-docker-builder
├─ nexus-registry-manager
├─ nexus-backup-manager
└─ nexus-disaster-recovery

Applications (8)
├─ nexus-api-runner
├─ nexus-worker-queue
├─ nexus-scheduler-service
├─ nexus-webhook-receiver
├─ nexus-notification-service
├─ nexus-cache-manager
├─ nexus-database-migrator
└─ nexus-logging-aggregator

Monitoring (6)
├─ nexus-prometheus-collector
├─ nexus-alertmanager-runner
├─ nexus-grafana-datasource
├─ nexus-log-ingester
├─ nexus-trace-collector
└─ nexus-health-checker

Security (5)
├─ nexus-secrets-manager
├─ nexus-audit-logger
├─ nexus-security-scanner
├─ nexus-compliance-reporter
└─ nexus-incident-responder

Development (6)
├─ nexus-ci-runner
├─ nexus-test-automation
├─ nexus-load-tester
├─ nexus-e2e-tester
├─ nexus-integration-tester
└─ nexus-documentation-builder
```

### Security Features Enabled

✅ **SSH_ASKPASS=none** - Prevents password prompts at OS level  
✅ **PasswordAuthentication=no** - Server rejects all password attempts  
✅ **BatchMode=yes** - No interactive SSH input allowed  
✅ **Ed25519 Keys** - 256-bit ECDSA (FIPS 186-4)  
✅ **GSM Storage** - AES-256 encryption at rest  
✅ **90-Day Rotation** - Automatic credential lifecycle  
✅ **Immutable Audit** - JSONL append-only logging  
✅ **Health Monitoring** - Hourly automated checks  

---

## Deployment Architecture

```
Step 1: Generate Ed25519 Keys (All 32)
    ↓
Step 2: Store in GSM (Encrypted AES-256)
    ↓
Step 3: Deploy Public Keys to Targets (.42, .39)
    ↓
Step 4: Configure Local SSH Environment (~/.ssh/svc-keys/)
    ↓
Step 5: Enable Systemd Automation
    ↓
Step 6: Verify All Connections (No Password Prompts)
    ↓
🟢 Production Ready
```

---

## Key Files Created/Updated

### Deployment Scripts
- `scripts/ssh_service_accounts/deploy_all_32_accounts.sh` - Master deployment (NEW)
- `scripts/ssh_service_accounts/generate_keys.sh` - Key generation (existing)
- `scripts/ssh_service_accounts/automated_deploy_keys_only.sh` - Individual account deployment
- `scripts/ssh_service_accounts/health_check.sh` - Health monitoring
- `scripts/ssh_service_accounts/credential_rotation.sh` - Rotation automation
- `scripts/ssh_service_accounts/orchestrate.sh` - Operations orchestrator

### Systemd Automation
- `services/systemd/service-account-health-check.service` - Health check service (NEW)
- `services/systemd/service-account-health-check.timer` - Hourly timer (NEW)
- `services/systemd/service-account-credential-rotation.service` - Rotation service (NEW)
- `services/systemd/service-account-credential-rotation.timer` - Monthly timer (NEW)

### Governance Documents
- `docs/governance/SSH_KEY_ONLY_MANDATE.md` - Policy enforcement
- `docs/architecture/SERVICE_ACCOUNT_ARCHITECTURE.md` - 32 account taxonomy
- `docs/architecture/SSH_10X_ENHANCEMENTS.md` - Enhancement roadmap
- `docs/deployment/SSH_DEPLOYMENT_CHECKLIST.md` - Verification procedures
- `.instructions.md` - Repository rules (UPDATED)

### Output Artifacts
- `logs/deployment/deployment-all-accounts-*.log` - Complete deployment log
- `logs/audit-trail.jsonl` - Immutable audit trail (append-only)
- `.deployment-state/{account}/.deployed` - Deployment markers
- `secrets/ssh/{account}/id_ed25519` - Private keys (local, git-ignored)
- `~/.ssh/svc-keys/` - Local SSH key distribution

---

## Validation & Testing

### Pre-Deployment Validation

```bash
# Verify SSH_ASKPASS disabled
echo $SSH_ASKPASS  # Should show: none

# Verify PasswordAuthentication disabled
grep "PasswordAuthentication no" ~/.ssh/config

# Verify no password mechanisms
grep -r "sshpass\|expect\|read -s" scripts/ssh_service_accounts/

# Test no password prompts
timeout 2 ssh -o BatchMode=yes -i ~/.ssh/test_key test@127.0.0.1 whoami 2>&1 | \
  grep -qE "Permission denied|Connection refused"
```

### Post-Deployment Validation

```bash
# Health check for all accounts
bash scripts/ssh_service_accounts/health_check.sh report

# Verify audit trail populated
jq -s 'length' logs/audit-trail.jsonl

# Test specific account
ssh -o BatchMode=yes \
    -i ~/.ssh/svc-keys/nexus-api-runner_key \
    nexus-api-runner@192.168.168.42 "whoami && id"

# Verify idempotency (run 3x, should be identical)
for i in 1 2 3; do
  bash scripts/ssh_service_accounts/health_check.sh report > /tmp/health-$i.txt
done
diff /tmp/health-1.txt /tmp/health-2.txt && diff /tmp/health-2.txt /tmp/health-3.txt
```

---

## Monitoring & Alerts

### Health Dashboard

```bash
# View recent health checks
sudo journalctl -u service-account-health-check.service -n 50 --no-pager

# Check timer next run
sudo systemctl list-timers service-account-health-check.timer

# View credential rotation schedule
sudo systemctl list-timers service-account-credential-rotation.timer
```

### Alert Integration

Alerts triggered on:
- ❌ SSH key rotation overdue (90+ days)
- ❌ Connection failures increasing
- ❌ Password prompt detected (security breach!)
- ❌ Unauthorized key usage anomaly
- ❌ GSM/Vault connectivity loss

### Audit Trail Monitoring

```bash
# Real-time audit tail
tail -f logs/audit-trail.jsonl | jq '.event_type, .status'

# Count SSH operations
jq -s 'group_by(.event_type) | map({type: .[0].event_type, count: length})' \
  logs/audit-trail.jsonl

# Find failures
jq '.[] | select(.status != "success")' logs/audit-trail.jsonl

# Check for password prompts (security issue!)
jq '.[] | select(.password_prompt == true)' logs/audit-trail.jsonl
```

---

## Troubleshooting

### Issue: SSH Connection Fails

**Symptom:** `Permission denied (publickey,password)`

**Diagnosis:**
```bash
# Check key permissions
stat -c '%a %U:%G' ~/.ssh/svc-keys/account_key  # Should be 600 root:root

# Verify public key on target
ssh root@192.168.168.42 'grep -c "ED25519" /home/account/.ssh/authorized_keys'

# Test SSH with verbose output
ssh -vvv -o BatchMode=yes \
    -i ~/.ssh/svc-keys/account_key \
    account@192.168.168.42 whoami
```

**Solution:**
```bash
# Fix permissions locally
chmod 600 ~/.ssh/svc-keys/account_key

# Fix permissions on target
ssh root@192.168.168.42 'chmod 600 /home/account/.ssh/authorized_keys'

# Redeploy if needed
bash scripts/ssh_service_accounts/deploy_all_32_accounts.sh
```

### Issue: Health Check Fails

**Symptom:** Health check shows accounts "UNHEALTHY"

**Diagnosis:**
```bash
# Check systemd timer logs
sudo journalctl -u service-account-health-check.timer -n 20

# Check if script is running
ps aux | grep health_check.sh

# Run health check manually with verbose output
bash -x scripts/ssh_service_accounts/health_check.sh report
```

### Issue: Password Prompt Appears (CRITICAL!)

**Symptom:** SSH prompts for password (security breach)

**Emergency Response:**
```bash
# 1. STOP all deployments
sudo systemctl stop nexusshield-auto-deploy.service
pkill -f "automated_deploy" || true

# 2. CHECK SSH_ASKPASS setting
echo $SSH_ASKPASS  # Must be: none

# 3. FIX SSH_ASKPASS
export SSH_ASKPASS=none
source ~/.bashrc

# 4. CHECK SSH config
grep "PasswordAuthentication" ~/.ssh/config

# 5. VERIFY no password prompts
timeout 2 ssh -o BatchMode=yes -i ~/.ssh/test_key test@127.0.0.1 whoami 2>&1

# 6. ALERT SECURITY TEAM
echo "SSH password prompt detected - investigate immediately" | \
  mail security@nexusshield.io
```

---

## Rollback Procedure

If needed to revert deployment:

```bash
# 1. Stop automation
sudo systemctl stop service-account-*.timer

# 2. Remove deployed keys from targets
for host in 192.168.168.42 192.168.168.39; do
  ssh root@$host 'find /home -name "authorized_keys" -exec mv {} {}.bak \;'
done

# 3. Restore from backup
for host in 192.168.168.42 192.168.168.39; do
  ssh root@$host 'find /home -name "authorized_keys.bak" -exec mv {} ${%}.bak} \;'
done

# 3. Reset local state
rm -rf .deployment-state/*

# 4. Restart with previous setup
bash scripts/ssh_service_accounts/automated_deploy_keys_only.sh
```

---

## Post-Deployment Checklist

After deployment completes:

- [ ] All 32 service accounts deployed (0 failures)
- [ ] Health checks enabled (hourly systemd timer running)
- [ ] Credential rotation enabled (monthly systemd timer running)
- [ ] SSH_ASKPASS=none set in environment
- [ ] PasswordAuthentication=no verified in SSH config
- [ ] No password prompts detected in any scenario
- [ ] Audit trail populated with SSH operations
- [ ] Keys backed up in GSM (AES-256 encrypted)
- [ ] Documentation updated with deployment details
- [ ] Team trained on new account usage

---

## Next Steps (Recommended)

### Immediate (Today)
1. ✅ Run `deploy_all_32_accounts.sh`
2. ✅ Enable systemd timers
3. ✅ Verify health checks
4. ✅ Confirm audit trail

### Week 1
- [ ] Monitor health check logs
- [ ] Test each account manually
- [ ] Verify GitOps integration
- [ ] Document any issues

### Month 1
- [ ] Implement 10X enhancements Phase 1
- [ ] HSM integration
- [ ] Multi-region replication
- [ ] Enhanced monitoring

### Ongoing
- [ ] 90-day credential rotation (automatic)
- [ ] Compliance audits (monthly)
- [ ] Security reviews (quarterly)
- [ ] Enhancement roadmap (annual)

---

## Support & Documentation

- **Policy:** `docs/governance/SSH_KEY_ONLY_MANDATE.md`
- **Architecture:** `docs/architecture/SERVICE_ACCOUNT_ARCHITECTURE.md`
- **Deployment:** `docs/deployment/SSH_DEPLOYMENT_CHECKLIST.md`
- **Enhancements:** `docs/architecture/SSH_10X_ENHANCEMENTS.md`
- **Logs:** `logs/deployment/deployment-all-accounts-*.log`

---

**Status:** 🟢 **READY TO EXECUTE**  
**Complexity:** Moderate (fully automated, zero manual steps needed)  
**Risk Level:** LOW (idempotent, reversible, no prod changes)  
**Time to Deploy:** ~10 minutes  
**Time to Verify:** ~5 minutes

**BEGIN DEPLOYMENT NOW** ✅
