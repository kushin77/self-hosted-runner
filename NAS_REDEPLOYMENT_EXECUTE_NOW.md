# 🚀 NAS REDEPLOYMENT - QUICK EXECUTION GUIDE

**Status**: READY TO EXECUTE  
**Date**: March 14, 2026  
**Estimated Time**: 30-45 minutes  
**Risk Level**: LOW (with full rollback capability)

---

## ⚡ QUICK START (Copy & Paste)

### Step 1: Make Scripts Executable

```bash
chmod +x /home/akushnir/self-hosted-runner/deploy-full-nas-redeployment.sh
chmod +x /home/akushnir/self-hosted-runner/verify-nas-redeployment.sh
```

### Step 2: Pre-Deployment Verification

```bash
# Quick connectivity check
/home/akushnir/self-hosted-runner/verify-nas-redeployment.sh quick
```

**Expected output**: All connectivity checks should pass (green ✓)

### Step 3: Dry-Run (Recommended First)

```bash
# See exactly what will be deployed without making changes
cd /home/akushnir/self-hosted-runner
./deploy-full-nas-redeployment.sh --dry-run full
```

**Expected output**: Shows all steps that would execute, but no actual deployment

### Step 4: Execute Full Redeployment

```bash
# Run the complete deployment
cd /home/akushnir/self-hosted-runner
./deploy-full-nas-redeployment.sh full
```

**This takes 12-18 minutes and will:**
- ✅ Validate all prerequisites
- ✅ Sync entire repository to NAS
- ✅ Deploy integration scripts to worker node
- ✅ Activate automated syncing (30-min intervals)
- ✅ Enable health checks (15-min intervals)
- ✅ Record audit trail

### Step 5: Verify Deployment

```bash
# Quick verification
/home/akushnir/self-hosted-runner/verify-nas-redeployment.sh quick

# Detailed verification (comprehensive)
/home/akushnir/self-hosted-runner/verify-nas-redeployment.sh detailed
```

**Expected**: 20+ checks passing, all green ✓

---

## 📊 REAL-TIME STATUS MONITORING

While deployment runs, in another terminal:

```bash
# Watch deployment progress
tail -f /home/akushnir/self-hosted-runner/.deployment-logs/nas-full-redeployment-*.log

# Check worker node timer status
watch -n 5 ssh automation@192.168.168.42 "sudo systemctl status nas-worker-sync.timer"
```

---

## ✅ POST-DEPLOYMENT VALIDATION

After deployment completes:

```bash
# 1. Check deployment completed successfully
echo "=== Deployment Log Summary ==="
tail -100 /home/akushnir/self-hosted-runner/.deployment-logs/nas-full-redeployment-*.log | grep -E "SUCCESS|FAILED"

# 2. Verify all services are active
echo "=== Service Status ==="
ssh automation@192.168.168.42 "sudo systemctl status nas-integration.target"

# 3. Check initial sync status
echo "=== Sync Status ==="
ssh automation@192.168.168.42 "ls -lh /opt/nas-sync/ 2>/dev/null | tail -5"

# 4. Verify NAS has files
echo "=== NAS Repository ==="
ssh automation@192.168.168.100 "find /repositories/self-hosted-runner -type f | wc -l"
```

---

## 🔄 AUTOMATED SYNC VERIFICATION  

After deployment, the system runs automatically:

```bash
# View next scheduled sync
ssh automation@192.168.168.42 "systemctl status nas-worker-sync.timer"

# Force immediate sync (if needed)
ssh automation@192.168.168.42 "sudo /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh"

# Monitor audit trail
ssh automation@192.168.168.42 "tail -20 /opt/nas-sync/audit/*.jsonl"
```

---

## 📋 DEPLOYMENT COMMANDS BY PHASE

### Phase-Specific Commands (If Needed)

```bash
# 1. Preflight checks only
./deploy-full-nas-redeployment.sh preflight

# 2. Sync repository only
./deploy-full-nas-redeployment.sh sync

# 3. Deploy scripts and systemd only
./deploy-full-nas-redeployment.sh deploy

# 4. Verify only
./deploy-full-nas-redeployment.sh verify
```

---

## 🔙 ROLLBACK (If Anything Goes Wrong)

```bash
# Disable NAS integration immediately
./deploy-full-nas-redeployment.sh rollback

# Verify rollback
ssh automation@192.168.168.42 "sudo systemctl status nas-integration.target"
# Should show: "inactive (dead)"

# To restore after rollback, just re-run:
./deploy-full-nas-redeployment.sh full
```

---

## 📊 VERIFICATION MODE GUIDE

```bash
# Quick (2 min) - Just connectivity & services
./verify-nas-redeployment.sh quick

# Detailed (5 min) - Connectivity, NAS storage, worker, services, logs
./verify-nas-redeployment.sh detailed

# Comprehensive (10 min) - Everything including security & apps
./verify-nas-redeployment.sh comprehensive
```

---

## 🚨 TROUBLESHOOTING QUICK COMMANDS

```bash
# If SSH is failing
ssh -v automation@192.168.168.100 "exit 0"

# If NAS storage is full
ssh automation@192.168.168.100 "df -h /repositories"

# If worker disk is full
ssh automation@192.168.168.42 "df -h /opt"

# If sync isn't running
ssh automation@192.168.168.42 "sudo systemctl restart nas-worker-sync.timer"

# If you need to manually force sync
ssh automation@192.168.168.42 "sudo /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh"

# Check detailed error logs
cat /home/akushnir/self-hosted-runner/.deployment-logs/nas-full-redeployment-*.log | grep ERROR

# Check audit trail for failures
cat /home/akushnir/self-hosted-runner/.deployment-logs/audit-trail-*.jsonl | jq 'select(.status=="FAILED")'
```

---

## 📞 REFERENCE

### Key Paths
- **Deployment Script**: `/home/akushnir/self-hosted-runner/deploy-full-nas-redeployment.sh`
- **Verification Script**: `/home/akushnir/self-hosted-runner/verify-nas-redeployment.sh`
- **Full Runbook**: `/home/akushnir/self-hosted-runner/NAS_FULL_REDEPLOYMENT_RUNBOOK.md`
- **Log Directory**: `/home/akushnir/self-hosted-runner/.deployment-logs/`
- **Worker Sync Dir**: `/opt/nas-sync/` (on worker node)
- **NAS Repo**: `/repositories/self-hosted-runner/` (on NAS)

### Key IPs
- **Dev Node**: 192.168.168.31 (development machine)
- **Worker Node**: 192.168.168.42 (production compute)
- **NAS Server**: 192.168.168.100 (centralized storage)

### Systemd Services (on worker)
- `nas-worker-sync.service` - Primary sync service
- `nas-worker-sync.timer` - Runs sync every 30 minutes
- `nas-worker-healthcheck.service` - Health check service
- `nas-worker-healthcheck.timer` - Runs health check every 15 minutes
- `nas-integration.target` - Aggregates all NAS services

---

## 🎯 SUCCESS CRITERIA

After deployment, you should see:

✅ All deployment logs show `[SUCCESS]`  
✅ Systemd timers are active on worker node  
✅ NAS repository has all files synced  
✅ Worker node receives configuration from NAS  
✅ Audit trail is recording events  
✅ No errors in verification results  
✅ Services continue working normally  
✅ Health checks run automatically every 15 minutes  
✅ Configuration syncs from NAS every 30 minutes  

---

## 📝 NEXT STEPS

1. **Review** the full runbook: [NAS_FULL_REDEPLOYMENT_RUNBOOK.md](NAS_FULL_REDEPLOYMENT_RUNBOOK.md)
2. **Execute** quick connectivity test first: `verify-nas-redeployment.sh quick`
3. **Run** dry-run to see what will happen: `deploy-full-nas-redeployment.sh --dry-run full`
4. **Execute** full deployment: `deploy-full-nas-redeployment.sh full`
5. **Verify** deployment success: `verify-nas-redeployment.sh detailed`

**Estimated total time**: 40 minutes (including dry-run and verification)

---

🚀 **Ready to deploy!** Run the commands above to redeploy your entire repository environment to NAS storage.

Any issues? Check the troubleshooting section or review deployment logs in `.deployment-logs/`
