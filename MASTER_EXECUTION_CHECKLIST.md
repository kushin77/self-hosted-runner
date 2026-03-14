# MASTER DEPLOYMENT EXECUTION CHECKLIST

## ✅ Pre-Execution Phase (5 minutes)

### Preparation on Developer Machine

**Task 1: Verify Prerequisies**
- [ ] Have USB drive available (8GB+ recommended)
- [ ] Developer machine has bash, git, docker (optional)
- [ ] Read `WORKER_DEPLOYMENT_IMPLEMENTATION.md` (5 min)
- [ ] Choose transfer method (USB recommended)

**Task 2: Prepare Deployment Package**
```bash
cd /home/akushnir/self-hosted-runner
bash prepare-deployment-package.sh
# Select Option 1 (USB) - RECOMMENDED
```
- [ ] Script runs without errors
- [ ] USB drive detected
- [ ] Mount point confirmed
- [ ] Archive created and transferred

**Task 3: Prepare Worker Node**
- [ ] Verify hostname is `dev-elevatediq`
- [ ] Verify IP is `192.168.168.42`
- [ ] Check 100+ MB disk space in /opt
- [ ] Verify required commands (bash, git, curl, etc.)
- [ ] Eject USB from developer machine safely

---

## ✅ USB Transfer Phase (2 minutes)

### Physical Transfer

**Task 4: Move USB to Worker Node**
- [ ] Eject USB from developer machine
- [ ] Physically transfer USB to dev-elevatediq
- [ ] Insert USB into target machine

**Task 5: Mount USB on Worker Node**
```bash
sudo mkdir -p /media/usb
sudo mount /dev/sdb1 /media/usb  # Adjust device name if needed
ls -la /media/usb  # Verify USB mounted
```
- [ ] USB mount directory created
- [ ] USB successfully mounted
- [ ] Files visible in /media/usb

---

## ✅ Deployment Phase (3 minutes)

### Execute Deployment Script on Worker Node

**Task 6: Extract Deployment Archive**
```bash
cd /media/usb
tar -xzf automation-deployment-*.tar.gz
ls -la automation-deployment-*/  # Verify extraction
```
- [ ] Archive extracted successfully
- [ ] deployment/ directory visible
- [ ] deploy-standalone.sh present

**Task 7: Run Deployment Script**
```bash
cd automation-deployment-*/
bash deployment/deploy-standalone.sh
# Monitor output for "✅ DEPLOYMENT COMPLETE"
```
- [ ] Script starts with no permission errors
- [ ] Prerequisite checks pass ✅
- [ ] Repository clones successfully
- [ ] All 8 scripts deploy with ✅ marks
- [ ] Verification passes (12/12 checks)
- [ ] Script ends with "✅ DEPLOYMENT COMPLETE"

**Task 8: Monitor Deployment (Real-time)**
```bash
# In another terminal:
tail -f /opt/automation/audit/deployment-*.log
```
- [ ] Can see real-time deployment progress
- [ ] No ERROR messages appear
- [ ] Deployment completes in ~3 minutes

---

## ✅ Verification Phase (2 minutes)

### Immediate Verification on Worker Node

**Task 9: Verify Installation Structure**
```bash
ls -laR /opt/automation/
```
Expected output:
- [ ] `/opt/automation/k8s-health-checks/` exists (3 scripts)
- [ ] `/opt/automation/security/` exists (1 script)
- [ ] `/opt/automation/multi-region/` exists (1 script)
- [ ] `/opt/automation/core/` exists (3 scripts)
- [ ] `/opt/automation/audit/` exists with log file

**Task 10: Count Scripts**
```bash
find /opt/automation -name "*.sh" | wc -l
# Should output: 8
```
- [ ] Result is exactly 8
- [ ] No scripts missing or extra

**Task 11: Verify Execution Permissions**
```bash
find /opt/automation -name "*.sh" -type f | while read f; do
  [ -x "$f" ] && echo "✓ $(basename $f)" || echo "✗ $(basename $f)"
done
# All should show ✓
```
- [ ] All 8 scripts show ✓ (executable)
- [ ] No ✗ (permission denied) marks

**Task 12: Test Bash Syntax**
```bash
for f in /opt/automation/*/*.sh; do
  bash -n "$f" && echo "✓ Syntax: $(basename $f)" || echo "✗ Error: $f"
done
# All should show ✓
```
- [ ] All 8 scripts show ✓ (valid syntax)
- [ ] No ✗ (syntax error) marks

**Task 13: Review Deployment Log**
```bash
cat /opt/automation/audit/deployment-*.log | tail -20
# Should end with "✅ DEPLOYMENT COMPLETE"
```
- [ ] Log file exists and is readable
- [ ] Log ends with "✅ DEPLOYMENT COMPLETE"
- [ ] All 8 components listed with ✅
- [ ] No ERROR messages in log

**Task 14: Test One Component**
```bash
bash /opt/automation/k8s-health-checks/cluster-readiness.sh --check-only
# Should complete with status
```
- [ ] Script runs without errors
- [ ] Produces expected output
- [ ] Returns success status

---

## ✅ Post-Deployment Phase (Optional)

### Setup Automation (Optional - 10 minutes)

**Task 15: Setup Logging Directory (Optional)**
```bash
sudo mkdir -p /var/log/automation
sudo chmod 755 /var/log/automation
```
- [ ] Logging directory created
- [ ] Proper permissions set

**Task 16: Schedule Health Checks (Optional)**
```bash
sudo crontab -e
# Add this line:
# */5 * * * * /opt/automation/k8s-health-checks/cluster-readiness.sh --quiet >> /var/log/automation/health-checks.log 2>&1
```
- [ ] Crontab edited successfully
- [ ] Health check job added
- [ ] Job scheduled for every 5 minutes

**Task 17: Schedule Security Audits (Optional)**
```bash
# In crontab, add:
# 0 2 * * * /opt/automation/security/audit-test-values.sh --report > /var/log/automation/audit-$(date +\%Y\%m\%d).log 2>&1
```
- [ ] Audit job added
- [ ] Job scheduled for 2 AM daily

**Task 18: Schedule Credential Rotation (Optional)**
```bash
# In crontab, add:
# 0 */6 * * * /opt/automation/core/credential-manager.sh --rotate >> /var/log/automation/cred-rotation.log 2>&1
```
- [ ] Credential rotation job added
- [ ] Job scheduled for every 6 hours

**Task 19: Verify Cron Jobs (Optional)**
```bash
sudo crontab -l | grep automation
# Should list 3+ automation jobs
```
- [ ] At least 3 automation jobs visible
- [ ] All jobs point to /opt/automation
- [ ] Proper log redirection set

---

## ✅ Final Validation (2 minutes)

### Confirm Complete Success

**Checklist: All Components Present**
```bash
ls /opt/automation/{k8s-health-checks,security,multi-region,core,audit}/*.sh | wc -l
# Should output: 8
```
- [ ] Exactly 8 scripts present

**Checklist: All Scripts Functional**
```bash
for f in /opt/automation/*/*.sh; do
  grep -q "^#!/bin/bash" "$f" && echo "✓ $(basename $f)" || echo "✗ $(basename $f)"
done
```
- [ ] All 8 scripts have shebang line
- [ ] All valid bash scripts

**Checklist: Audit Trail Complete**
```bash
[ -f /opt/automation/audit/deployment-*.log ] && echo "✓ Audit log present" || echo "✗ No audit log"
```
- [ ] Audit log file exists
- [ ] Contains deployment session ID
- [ ] Contains deployment timestamp

**Checklist: Success Markers**
```bash
grep "✅ DEPLOYMENT COMPLETE" /opt/automation/audit/deployment-*.log && echo "✓" || echo "✗"
```
- [ ] Log contains "✅ DEPLOYMENT COMPLETE"
- [ ] Indicates successful deployment

---

## 📊 Summary Checklist

### Phase 1: Preparation
- [ ] USB drive prepared
- [ ] Documentation reviewed
- [ ] Prerequisites checked
- [ ] Package creation complete

### Phase 2: Transfer
- [ ] USB transferred to worker node
- [ ] USB mounted successfully
- [ ] Archive extracted

### Phase 3: Deployment
- [ ] deploy-standalone.sh executed
- [ ] All 8 components deployed
- [ ] Verification passed (12/12)
- [ ] Log shows completion

### Phase 4: Verification
- [ ] 8 scripts confirmed present
- [ ] All scripts executable
- [ ] Bash syntax validated
- [ ] Deployment log exists
- [ ] At least one component tested

### Phase 5: Automation (Optional)
- [ ] Logging directory created
- [ ] Cron jobs scheduled
- [ ] Jobs verified

---

## ✅ COMPLETE SUCCESS CRITERIA

Mark each criterion as verified:

| Criterion | Verified | Notes |
|-----------|----------|-------|
| 8 scripts present | ☐ | `find /opt/automation -name "*.sh" \| wc -l = 8` |
| All executable | ☐ | All show `-rwxr-xr-x` |
| Syntax valid | ☐ | `bash -n` passes for all |
| Log file exists | ☐ | `/opt/automation/audit/deployment-*.log` |
| Log shows success | ☐ | Contains "✅ DEPLOYMENT COMPLETE" |
| No errors in log | ☐ | No ERROR or FAILED messages |
| Components functional | ☐ | `cluster-readiness.sh --check-only` works |
| Cron jobs scheduled | ☐ | Optional - only if enabled |

**Total Success = All items ☑**

---

## 🚨 TROUBLESHOOTING QUICK REFERENCE

### Deployment Script Won't Start
```bash
# Check permissions
ls -la /media/usb/automation-deployment-*/deployment/deploy-standalone.sh
# Make executable if needed
chmod +x deploy-standalone.sh
```

### Scripts Missing After Deployment
```bash
# Check count
find /opt/automation -name "*.sh" | wc -l  # Should be 8

# If less than 8, check log for errors
tail -50 /opt/automation/audit/deployment-*.log | grep -i error
```

### Permission Denied Errors
```bash
# Check directory ownership
ls -ld /opt/automation

# Fix if needed
sudo chmod 755 /opt/automation
sudo chmod 755 /opt/automation/*
```

### Disk Space Issues
```bash
# Check available space
df -h /opt

# If low, clean up
sudo rm -rf /opt/automation/audit/deployment-*.log  # Keep only recent
```

### Git Clone Fails
```bash
# Check network
ping github.com

# Verify certificate
curl -I https://github.com
```

---

## 📞 SUPPORT CONTACTS

### Self-Service Resources
1. **WORKER_DEPLOYMENT_README.md** - Section 7 (Troubleshooting)
2. **DEPLOYMENT_EXPECTED_OUTPUT.md** - Compare your output
3. **Deployment log** - `/opt/automation/audit/deployment-*.log`

### Manual Steps if Automated Deployment Fails
1. See WORKER_DEPLOYMENT_README.md Section 9 (Manual Deployment)
2. Create directories manually:
   ```bash
   sudo mkdir -p /opt/automation/{k8s-health-checks,security,multi-region,core,audit}
   ```
3. Clone repo manually:
   ```bash
   git clone https://github.com/kushin77/self-hosted-runner.git
   cd self-hosted-runner
   # Copy scripts manually to locations
   ```

---

## ⏱ TIME ALLOCATION

| Phase | Min | Max | Notes |
|-------|-----|-----|-------|
| Preparation | 5 | 10 | Include reading documentation |
| Transfer | 1 | 3 | Depends on USB transfer speed |
| Deployment | 3 | 5 | Includes download & deploy |
| Verification | 1 | 2 | Quick checks |
| Automation Setup | 0 | 10 | Optional cron jobs |
| **TOTAL** | **10** | **30** | Varies by options selected |

---

## 📋 DOCUMENTATION QUICK LINKS

| Document | When to Read | Time |
|----------|--------------|------|
| WORKER_DEPLOYMENT_IMPLEMENTATION.md | Before starting | 5 min |
| WORKER_DEPLOYMENT_README.md | During deployment | As needed |
| DEPLOYMENT_EXPECTED_OUTPUT.md | To compare results | 5 min |
| WORKER_DEPLOYMENT_TRANSFER_GUIDE.md | If transfer fails | As needed |
| SSH_DEPLOYMENT_FAILURE_RESOLUTION.md | For status updates | 5 min |

---

## 🎯 SUCCESS STATEMENT

**"Deployment is successful when all 8 scripts are present in `/opt/automation/`, 
executable, syntax-validated, and the audit log shows '✅ DEPLOYMENT COMPLETE' 
with no errors."**

---

## NEXT STEP: START EXECUTION

```
Current Status: ✅ Ready
Your Next Action: Complete this checklist
Expected Completion: 30 minutes
```

**START WITH:**
1. ✅ Read: WORKER_DEPLOYMENT_IMPLEMENTATION.md (5 min)
2. ✅ Run: bash prepare-deployment-package.sh (5 min)
3. ✅ Transfer: Move USB to worker node (2 min)
4. ✅ Execute: bash deployment/deploy-standalone.sh (3 min)
5. ✅ Verify: Complete verification checklist (2 min)

---

**Document Version:** 1.0  
**Target:** dev-elevatediq (192.168.168.42)  
**Status:** Ready for Execution  
**Estimated Total Time:** 17-30 minutes (depending on options)
