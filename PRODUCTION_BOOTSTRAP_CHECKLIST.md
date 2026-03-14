# 🚀 PRODUCTION BOOTSTRAP CHECKLIST

**Mandate Status:** 100% Approved & Executed  
**Framework Status:** Production Ready (Stages 1-2 ✅)  
**Next Phase:** Infrastructure Prerequisites → Production Deployment  

---

## Phase 1: NAS Server Configuration (Issue #3172)

### Verify NAS Accessibility
```bash
# From any node that should connect
ping -c 3 192.16.168.39
ssh root@192.16.168.39 "uname -a"
```

### Configure NAS Exports
Run on NAS server (192.16.168.39) as root:
```bash
# Append to /etc/exports
sudo tee -a /etc/exports <<'EOX'
/repositories *.168.168.0/24(rw,sync,no_subtree_check)
/config-vault *.168.168.0/24(rw,sync,no_subtree_check)
EOX

# Apply exports
sudo exportfs -r
sudo exportfs -v

# Verify output contains:
# /repositories         *.168.168.0/24
# /config-vault         *.168.168.0/24
```

### Validation
```bash
# From worker node (192.168.168.42)
showmount -e 192.16.168.39

# Expected output:
# Export list for 192.16.168.39:
# /repositories *.168.168.0/24
# /config-vault *.168.168.0/24
```

✅ **Acceptance:** Issue #3172 - Mark as COMPLETE

---

## Phase 2: Worker Node Service Account (Issue #3170)

### Create Service Account
Run on worker node (192.168.168.42) as root/sudo:
```bash
# Create service account
sudo useradd -m -s /bin/bash svc-git

# Verify creation
id svc-git

# Create .ssh directory
sudo -u svc-git mkdir -p /home/svc-git/.ssh
sudo chmod 700 /home/svc-git/.ssh

# Verify permissions
ls -ld /home/svc-git/.ssh
# Should show: drwx------
```

### Grant Sudo Access (Optional, for NFS troubleshooting)
```bash
# Only if needed for diagnostics
sudo usermod -aG wheel svc-git
# Or specific sudoers line for targeted commands
```

### Validation
```bash
# Verify on worker
id svc-git
stat /home/svc-git

# Try login
sudo su - svc-git
whoami  # Should return: svc-git
```

✅ **Acceptance:** Issue #3170 - Mark as COMPLETE

---

## Phase 3: SSH Keys in GCP Secret Manager (Issue #3171)

### Verify GCP Authentication
```bash
gcloud auth login
gcloud config get-value project
```

### Store SSH Key in Secret Manager
```bash
# Create secret from existing SSH key
gcloud secrets create svc-git-ssh-key \
  --data-file=$HOME/.ssh/id_ed25519 \
  --labels=component=deployment,constraint=ephemeral,environment=production

# Verify creation
gcloud secrets describe svc-git-ssh-key
gcloud secrets versions list svc-git-ssh-key
```

### Set Access Permissions
```bash
# Grant access to worker node's service account (if using GCP service accounts)
# Or for manual access:
gcloud secrets add-iam-policy-binding svc-git-ssh-key \
  --member=user:$(gcloud config get-value account) \
  --role=roles/secretmanager.secretAccessor
```

### Validation
```bash
# Verify key retrieval
gcloud secrets versions access latest --secret=svc-git-ssh-key | head -c 50

# Should output ED25519 key header (-----BEGIN OPENSSH PRIVATE KEY-----)
```

✅ **Acceptance:** Issue #3171 - Mark as COMPLETE

---

## Phase 4: Pre-Production Verification

### Network Connectivity Check
```bash
# Run from dev machine
bash verify-nas-redeployment.sh quick

# Expected output:
# ✓ Worker reachable (192.168.168.42)
# ✓ NAS exports visible
# ✓ SSH connectivity confirmed
```

### NFS Mount Simulation
```bash
# From worker node, test NFS mount (don't persist yet)
sudo mount -t nfs4 -o proto=tcp,hard,retrans=3 \
  192.16.168.39:/repositories /mnt/test-repositories

# Verify mount
mount | grep test-repositories
ls -la /mnt/test-repositories

# Unmount test
sudo umount /mnt/test-repositories
```

### Orchestrator Dry-Run
```bash
# From dev machine (with SSH to worker)
# Validate stages without actual deployment
bash deploy-orchestrator.sh validate
```

---

## Phase 5: Production Deployment (Issue #3173)

### Execute Orchestrator
```bash
cd /home/akushnir/self-hosted-runner

# Run full 8-stage deployment
bash deploy-orchestrator.sh full 2>&1 | tee orchestration-production-$(date +%s).log

# Monitor execution
watch -n 5 'tail -50 orchestration-production-*.log | head -30'
```

### Expected Output Sequence
```
✅ Stage 1: Constraint Validation - PASSED
✅ Stage 2: Preflight Checks - PASSED
✅ Stage 3: NAS NFS Mounts - DEPLOYED
   └─ Systemd mount units created
   └─ Health check timer enabled
   └─ Sync automation initialized
✅ Stage 4: Worker Node Stack - DEPLOYED
✅ Stage 5: Systemd Automation - ENABLED
   ├─ 30-min sync timer enabled
   ├─ 15-min health check timer enabled
   └─ Integration target configured
✅ Stage 6: Comprehensive Verification - PASSED
✅ Stage 7: GitHub Issue Tracking - COMPLETED
   └─ Issue #3173 marked COMPLETE
✅ Stage 8: Immutable Git Commit - CREATED
```

### Immediate Post-Deployment Validation
```bash
# Verify NFS mounts active
mount | grep nas

# Verify systemd timers
systemctl --user list-timers  # Or system timers
systemctl status nas-sync.timer
systemctl status nas-health-check.timer

# Check latest deployment logs
tail -50 .deployment-logs/orchestrator-*.log
```

✅ **Acceptance:** Issue #3173 - Mark as COMPLETE

---

## Phase 6: Production Operations (Ongoing)

### Daily Verification
```bash
# Quick validation
bash verify-nas-redeployment.sh quick

# Detailed check (10 minutes)
bash verify-nas-redeployment.sh detailed

# Comprehensive audit (15 minutes)
bash verify-nas-redeployment.sh comprehensive
```

### Monitoring Automation
```bash
# Systemd timers run automatically:
# - Every 30 minutes: Sync repositories from canonical NAS
# - Every 15 minutes: Health check and validation
# - Zero manual intervention required

# View recent automation logs
journalctl -u nas-sync.timer -n 50
journalctl -u nas-health-check.timer -n 50
```

### Troubleshooting
```bash
# If issues occur, check logs
tail -100 .deployment-logs/nas-sync-*.log
tail -100 .deployment-logs/nas-health-check-*.log

# Re-run orchestrator verification (idempotent, safe)
bash deploy-orchestrator.sh verify comprehensive

# Manual re-deployment (idempotent, safe)
bash deploy-orchestrator.sh full
```

---

## ✅ Mandate Compliance Verification

After completing all phases:

```bash
# Verify all 8 constraints still enforced
bash deploy-orchestrator.sh verify comprehensive

# Expected: 100% compliance score
# ✓ Immutable (NAS canonical source verified)
# ✓ Ephemeral (no persistent state found)
# ✓ Idempotent (safe to re-run confirmed)
# ✓ No-Ops (automation confirmed running)
# ✓ Hands-Off (systemd timers active)
# ✓ GSM/Vault/KMS (SSH key in Secret Manager)
# ✓ Direct deployment (no GitHub Actions)
# ✓ On-prem only (cloud check passed)
```

---

## 📋 Quick Reference Commands

### Infrastructure Setup
```bash
# 1. NAS Server (192.16.168.39)
sudo exportfs -r && sudo exportfs -v

# 2. Worker Node (192.168.168.42)
sudo useradd -m -s /bin/bash svc-git

# 3. Secret Manager
gcloud secrets create svc-git-ssh-key --data-file=$HOME/.ssh/id_ed25519
```

### Production Deployment
```bash
# Main command
bash deploy-orchestrator.sh full

# Verify completion
bash deploy-orchestrator.sh verify comprehensive

# Check ongoing automation
systemctl --user list-timers  # Adjust for your system's timer location
```

### Monitoring
```bash
# Quick check (5 min)
bash verify-nas-redeployment.sh quick

# Full audit (15 min)
bash verify-nas-redeployment.sh comprehensive
```

---

## 🎯 Success Criteria

After completing all phases:

- ✅ NAS exports configured and verified
- ✅ svc-git service account created on worker
- ✅ SSH keys stored in GCP Secret Manager
- ✅ Orchestrator executed all 8 stages successfully
- ✅ Systemd timers (30-min sync, 15-min health checks) active
- ✅ All 8 constraints operationally verified
- ✅ 24/7 unattended operation confirmed
- ✅ Immutable deployment record created in git

**Result:** Mandate 100% Fulfilled ✅

---

**Prepared:** March 14, 2026  
**Status:** Ready for Infrastructure Setup  
**Next:** Execute Phase 1-5 per this checklist

