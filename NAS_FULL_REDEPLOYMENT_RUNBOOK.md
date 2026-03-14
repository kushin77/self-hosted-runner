# 🚀 FULL REPOSITORY REDEPLOYMENT TO NAS STORAGE

**Date**: March 14, 2026  
**Status**: PRODUCTION READY  
**Estimated Duration**: 30-45 minutes  
**Risk Level**: LOW (fully automated with rollback)

---

## 📋 Executive Summary

This document provides step-by-step instructions for redeploying the entire repository environment onto the new NAS storage (192.168.168.100). The redeployment:

✅ Syncs all repository code to NAS as the canonical source  
✅ Deploys NAS integration scripts to worker node (192.168.168.42)  
✅ Activates automated 30-minute sync intervals  
✅ Enables 15-minute health checks  
✅ Records immutable audit trail  
✅ Supports rollback if needed

---

## 🏗️ Architecture

```
Your Dev Machine             NAS Server                 Worker Node
(192.168.168.31)         (192.168.168.100)            (192.168.168.42)
      │                        │                             │
      ├─ Edit configs ────────►├─ Canonical Source  ────────┤
      │                        │                             │
      │  ssh/git               ├─ /repositories/*            │ Pull every 30min
      │                        ├─ /config-vault/*            │ (automated)
      │                        ├─ /audit-trails/*            │
      │                        │                             │
      │                   GCP Secret Manager ◄─ Fetch credentials
      │                        │
      └─── Manual backups ────►│
```

---

## ⚙️ PHASE 1: PRE-REDEPLOYMENT CHECKLIST

### 1.1 Network Verification

```bash
# Test connectivity to NAS
ssh -o ConnectTimeout=5 automation@192.168.168.100 "echo 'NAS OK'"

# Test connectivity to worker node
ssh -o ConnectTimeout=5 automation@192.168.168.42 "echo 'Worker OK'"

# Test bidirectional connectivity
ssh automation@192.168.168.42 "ssh -o ConnectTimeout=5 automation@192.168.168.100 'echo Bidirectional OK'"
```

### 1.2 SSH Key Verification

Ensure SSH keys are configured on both nodes:

```bash
# On dev node (.31) - check SSH access
ssh-keygen -i ~/.ssh/id_ed25519.pub  # Verify key exists

# On worker node (.42) - check SSH access
ssh automation@192.168.168.42 "ssh-keyscan -t ed25519 192.168.168.100 >> ~/.ssh/known_hosts"
```

### 1.3 Disk Space Check

```bash
# Check NAS disk space (need 50GB+)
ssh automation@192.168.168.100 "df -h /repositories"

# Check worker disk space (need 20GB+)
ssh automation@192.168.168.42 "df -h /opt"
```

### 1.4 Backup Current Configuration

```bash
# Create backup of current configuration on NAS
ssh automation@192.168.168.100 \
    "tar czf /backups/config-backup-$(date +%Y%m%d-%H%M%S).tar.gz /config-vault"

# Verify backup created
ssh automation@192.168.168.100 "ls -lh /backups/"
```

---

## 🚀 PHASE 2: EXECUTE FULL REDEPLOYMENT

### 2.1 Make Script Executable

```bash
chmod +x /home/akushnir/self-hosted-runner/deploy-full-nas-redeployment.sh
```

### 2.2 DRY-RUN (Optional but Recommended)

First, run in dry-run mode to see what will happen without making changes:

```bash
cd /home/akushnir/self-hosted-runner
./deploy-full-nas-redeployment.sh --dry-run full
```

**Expected output:**
```
[2026-03-14 HH:MM:SS] [INFO] Logging initialized
[2026-03-14 HH:MM:SS] [INFO] Starting Full NAS Redeployment
[2026-03-14 HH:MM:SS] [INFO] Running in DRY-RUN mode
[2026-03-14 HH:MM:SS] [INFO] Checking NAS connectivity...
[2026-03-14 HH:MM:SS] [SUCCESS] NAS server is reachable
... (more checks) ...
```

### 2.3 PRODUCTION DEPLOYMENT

Once dry-run succeeds, execute the full deployment:

```bash
cd /home/akushnir/self-hosted-runner
./deploy-full-nas-redeployment.sh full
```

**This will:**
1. ✅ Validate all prerequisites (2 min)
2. ✅ Sync repository to NAS (5-10 min depending on size)
3. ✅ Sync config files to NAS vault (1-2 min)
4. ✅ Deploy scripts to worker node (1 min)
5. ✅ Deploy systemd units (1 min)
6. ✅ Enable automated sync (1 min)
7. ✅ Verify deployment (2 min)

**Total time: 12-18 minutes**

### 2.4 Monitor Deployment Progress

In a separate terminal, monitor the deployment log:

```bash
# Watch the deployment log in real-time
tail -f /home/akushnir/self-hosted-runner/.deployment-logs/nas-full-redeployment-*.log

# Or in another terminal, check worker node sync status
watch -n 5 ssh automation@192.168.168.42 \
    "sudo systemctl status nas-worker-sync.timer"
```

---

## ✅ PHASE 3: VERIFICATION

### 3.1 Quick Verification (Immediate)

```bash
# Check deployment log
tail -50 /home/akushnir/self-hosted-runner/.deployment-logs/nas-full-redeployment-*.log

# Verify all services are active
ssh automation@192.168.168.42 "sudo systemctl status nas-integration.target"

# Check sync timer status
ssh automation@192.168.168.42 "sudo systemctl status nas-worker-sync.timer"

# Check health check timer status
ssh automation@192.168.168.42 "sudo systemctl status nas-worker-healthcheck.timer"
```

**Expected:** All should show `Active: active (waiting)` or `Active: active (running)`

### 3.2 Verify Files on NAS

```bash
# List repo files on NAS
ssh automation@192.168.168.100 "ls -lh /repositories/self-hosted-runner/ | head -20"

# Count files synced
ssh automation@192.168.168.100 "find /repositories/self-hosted-runner -type f | wc -l"

# Verify config vault
ssh automation@192.168.168.100 "ls -lh /config-vault/"
```

### 3.3 Verify Initial Sync on Worker

```bash
# Check if initial sync completed
ssh automation@192.168.168.42 "ls -lh /opt/nas-sync/ | head -20"

# Check sync logs
ssh automation@192.168.168.42 "tail -50 /opt/nas-sync/audit/*.jsonl | head -20"
```

### 3.4 Full Verification Script

Run the verification command to get a comprehensive status report:

```bash
cd /home/akushnir/self-hosted-runner
./deploy-full-nas-redeployment.sh verify
```

---

## 📊 PHASE 4: MONITORING & OPERATIONS

### 4.1 Automated Sync Schedule

Once deployed, the system automatically:

| Operation | Frequency | Purpose |
|-----------|-----------|---------|
| NAS sync | Every 30 minutes | Pull latest configs from NAS |
| Health check | Every 15 minutes | Validate sync, connectivity, disk |
| Credential fetch | On-demand (cached 5min) | Pull secrets from GCP Secret Manager |

### 4.2 Manual Sync (If Needed)

Force an immediate sync without waiting 30 minutes:

```bash
# SSH to worker node
ssh automation@192.168.168.42

# Run sync immediately
sudo /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Check sync status
tail -100 /opt/nas-sync/audit/sync-audit-*.jsonl
```

### 4.3 Health Check Status

View detailed health check information:

```bash
# SSH to worker node
ssh automation@192.168.168.42

# Run health check
sudo /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh

# View health check logs
tail -100 /opt/nas-sync/audit/health-*.jsonl
```

### 4.4 Audit Trail

All operations are recorded in immutable audit trail:

```bash
# View sync audit trail on NAS
ssh automation@192.168.168.100 \
    "tail -100 /audit-trails/sync-audit-*.jsonl"

# View audit trail on worker
ssh automation@192.168.168.42 \
    "tail -100 /opt/nas-sync/audit/*.jsonl"
```

---

## 🔧 TROUBLESHOOTING

### Issue: "NAS server is unreachable"

**Cause**: Network connectivity to NAS  
**Solution**:
```bash
# Check NAS IP is correct
ping 192.168.168.100

# Check SSH service on NAS
ssh automation@192.168.168.100 "systemctl status sshd"

# Check firewall on NAS
ssh automation@192.168.168.100 \
    "sudo ufw status | grep 22"
```

### Issue: "Worker node disk space is insufficient"

**Cause**: Worker node doesn't have 20GB free  
**Solution**:
```bash
# Check disk usage
ssh automation@192.168.168.42 "df -h /opt"

# Clean old logs/artifacts
ssh automation@192.168.168.42 \
    "sudo find /opt -name '*.log' -mtime +7 -delete"

# Run redeployment again
./deploy-full-nas-redeployment.sh full
```

### Issue: "rsync not found on worker node"

**Cause**: rsync is not installed  
**Solution**:
```bash
# Install rsync on worker
ssh automation@192.168.168.42 \
    "sudo apt-get update && sudo apt-get install -y rsync"

# Re-run sync
./deploy-full-nas-redeployment.sh sync
```

### Issue: "Systemd units failed to deploy"

**Cause**: File permissions or unit syntax error  
**Solution**:
```bash
# Check if systemd files exist
ls -l /home/akushnir/self-hosted-runner/systemd/

# Check syntax of failed unit
cat /home/akushnir/self-hosted-runner/systemd/nas-worker-sync.service

# Validate unit on worker
ssh automation@192.168.168.42 \
    "sudo systemd-analyze verify /etc/systemd/system/nas-worker-sync.service"
```

### Issue: "Initial sync hasn't completed"

**Cause**: Sync runs every 30 minutes, may need to wait  
**Solution**:
```bash
# Force immediate sync
ssh automation@192.168.168.42 \
    "sudo /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh"

# Wait and check results
sleep 10
ssh automation@192.168.168.42 "ls /opt/nas-sync/ | wc -l"
```

### Issue: "Can still access old configuration"

**Cause**: Worker node is using cached configuration  
**Solution**:
This is intentional for resilience! The worker node caches config locally.
- Current config is in: `/opt/nas-sync/`
- Config gets updated from NAS every 30 minutes automatically
- To force update: Run manual sync (see 4.2 above)

---

## 🔙 ROLLBACK

If anything goes wrong, rollback is simple:

```bash
# Disable NAS integration
./deploy-full-nas-redeployment.sh rollback

# This:
# - Stops all NAS timers
# - Disables automated sync
# - Preserves all data on NAS
# - Worker node returns to manual config management
```

To restore:
```bash
# Simply re-run the full deployment
./deploy-full-nas-redeployment.sh full
```

---

## 📋 POST-DEPLOYMENT CHECKLIST

- [ ] Deployment script completed without errors
- [ ] `verify` command shows all checks passed
- [ ] NAS server has replica of all repository files
- [ ] Worker node has received initial sync
- [ ] Systemd timers are active on worker node
- [ ] Health checks running every 15 minutes
- [ ] Audit trail is recording events
- [ ] Manual sync works: `ssh automation@192.168.168.42 "sudo /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh"`
- [ ] Portal/services are still accessible at normal endpoints
- [ ] No errors in deployment logs

---

## 📞 SUPPORT

### View Full Deployment Logs

```bash
cat /home/akushnir/self-hosted-runner/.deployment-logs/nas-full-redeployment-*.log
cat /home/akushnir/self-hosted-runner/.deployment-logs/audit-trail-*.jsonl
```

### Test Specific Components

```bash
# Test preflight only
./deploy-full-nas-redeployment.sh preflight

# Test sync only
./deploy-full-nas-redeployment.sh sync

# Test deployment only
./deploy-full-nas-redeployment.sh deploy

# Test verification only
./deploy-full-nas-redeployment.sh verify
```

### Emergency Contact

If something critical fails:
1. Review the deployment log (see above)
2. Check audit trail for specific failures
3. Rollback if needed: `./deploy-full-nas-redeployment.sh rollback`
4. Fix the underlying issue
5. Re-run: `./deploy-full-nas-redeployment.sh full`

---

## 📚 Related Documentation

- [NAS Integration Complete Guide](docs/NAS_INTEGRATION_COMPLETE.md)
- [NAS Quick Start](docs/NAS_QUICKSTART.md)
- [On-Premises Architecture](ON_PREMISES_ARCHITECTURE.md)
- [Operations Runbook](OPERATIONS_RUNBOOK.md)

---

**Status**: 🟢 PRODUCTION READY  
**Last Updated**: March 14, 2026  
**Approved**: Execution authorized
