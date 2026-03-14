# NAS Integration Deployment - Execution Guide

**Status**: 🟢 APPROVED FOR PRODUCTION DEPLOYMENT  
**Authorization**: Granted March 14, 2026  
**Timeline**: 10-15 minutes total execution time  
**Risk Level**: LOW (immutable, fully tested, idempotent)  

---

## DEPLOYMENT CHECKLIST

### Pre-Deployment (5 minutes)

- [ ] **Verify SSH access** to worker node (192.168.168.42)
- [ ] **Verify SSH access** to dev node (192.168.168.31)
- [ ] **Verify** `automation` user exists on both nodes
- [ ] **Verify** sudo access on both nodes for `systemctl` commands
- [ ] **Clone/pull** latest code: `git pull origin main`

### Deployment (10 minutes)

- [ ] **Deploy to Worker Node** (5 minutes)
  - SSH to 192.168.168.42
  - Execute worker deployment script
  - Verify directories created
  - Verify systemd services enabled
  
- [ ] **Deploy to Dev Node** (5 minutes)
  - SSH to 192.168.168.31
  - Execute dev deployment script
  - Verify service enabled

### Post-Deployment (5 minutes)

- [ ] **Verify Worker Sync** (2 minutes)
  - Check first sync occurred: `cat /opt/nas-sync/audit/.last-success`
  - Verify files in `/opt/nas-sync/iac`
  
- [ ] **Verify Health Checks** (1 minute)
  - Run health check: `bash /opt/automation/scripts/healthcheck-worker-nas.sh --verbose`
  
- [ ] **Monitor 24-hour cycle** (ongoing)
  - Automated timers handle all scheduling
  - No action required

---

## STEP-BY-STEP DEPLOYMENT

### STEP 1: Deploy to Worker Node (192.168.168.42)

Open terminal and execute:

```bash
# SSH to worker node
ssh automation@192.168.168.42

# Pull latest code
cd ~/self-hosted-runner
git pull origin main

# Create NAS directories
mkdir -p /opt/automation/scripts /opt/nas-sync/{iac,configs,credentials,audit}
chmod 700 /opt/nas-sync/credentials

# Install worker scripts
cp scripts/nas-integration/worker-node-nas-sync.sh /opt/automation/scripts/
cp scripts/nas-integration/healthcheck-worker-nas.sh /opt/automation/scripts/
chmod 755 /opt/automation/scripts/*.sh

# Install systemd services (requires sudo)
sudo cp systemd/nas-worker-sync.service /etc/systemd/system/
sudo cp systemd/nas-worker-sync.timer /etc/systemd/system/
sudo cp systemd/nas-worker-healthcheck.service /etc/systemd/system/
sudo cp systemd/nas-worker-healthcheck.timer /etc/systemd/system/
sudo cp systemd/nas-integration.target /etc/systemd/system/

# Enable and startservices
sudo systemctl daemon-reload
sudo systemctl enable nas-integration.target
sudo systemctl start nas-integration.target

# Verify services started
sudo systemctl list-timers | grep nas-

# Exit SSH session
exit
```

**Expected Output**:
```
NEXT                         LEFT          LAST                         PASSED UNIT                           ACTIVATION
Mon 2026-03-14 12:30:00 UTC  25min left    Mon 2026-03-14 12:00:00 UTC  5m ago nas-worker-sync.timer         nas-worker-sync.service
Mon 2026-03-14 12:15:00 UTC  10min left    Mon 2026-03-14 12:00:00 UTC  5m ago nas-worker-healthcheck.timer - nas-worker-healthcheck.service
```

---

### STEP 2: Deploy to Dev Node (192.168.168.31)

Open terminal and execute:

```bash
# SSH to dev node
ssh automation@192.168.168.31

# Pull latest code
cd ~/self-hosted-runner
git pull origin main

# Create directories
mkdir -p /opt/automation/scripts /opt/iac-configs

# Install dev push script
cp scripts/nas-integration/dev-node-nas-push.sh /opt/automation/scripts/
chmod 755 /opt/automation/scripts/dev-node-nas-push.sh

# Install systemd service
sudo cp systemd/nas-dev-push.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nas-dev-push.service

# Ready for use (optional: test one push now)
bash /opt/automation/scripts/dev-node-nas-push.sh push

# Exit SSH session
exit
```

**Expected Output** (on test push):
```
[✓] Validating NAS connectivity...
[✓] Source directory contains configs
[✓] Running rsync...
[✓] Push completed (0 seconds)
[+] Audit trail recorded
```

---

### STEP 3: Verify Worker Sync (Wait 30-60 seconds)

Back on your local machine:

```bash
# SSH to worker node
ssh automation@192.168.168.42

# Check first sync occurred
cat /opt/nas-sync/audit/.last-success

# Should show: success|2026-03-14T12:XX:XX+00:00|<hash>

# Verify files synced
find /opt/nas-sync/iac -type f | head -10

# Should show multiple files

# Run health check
bash /opt/automation/scripts/healthcheck-worker-nas.sh --verbose

# Expected: [✓] All health checks passed

# Exit SSH
exit
```

---

### STEP 4: Verify Systemd Timers (5 minute check)

```bash
# SSH to worker node
ssh automation@192.168.168.42

# Check timer status
sudo systemctl status nas-worker-sync.timer

# Check service logs
sudo journalctl -u nas-worker-sync.service -n 20

# Should show successful sync attempts

# Exit SSH
exit
```

---

## VERIFICATION CRITERIA

### ✅ Successful Worker Node Deployment

- [ ] Directory `/opt/nas-sync` exists with subdirectories
- [ ] Scripts in `/opt/automation/scripts/` are executable
- [ ] Systemd services active: `sudo systemctl list-units | grep nas`
- [ ] Timer status shows next run: `sudo systemctl status nas-worker-sync.timer`
- [ ] First sync succeeded: `cat /opt/nas-sync/audit/.last-success | grep success`
- [ ] Files synced to `/opt/nas-sync/iac` (≥5 files)
- [ ] Health check passes: health check script runs without errors

### ✅ Successful Dev Node Deployment

- [ ] Directory `/opt/automation/scripts` exists
- [ ] Script `dev-node-nas-push.sh` is executable
- [ ] Systemd service enabled: `sudo systemctl is-enabled nas-dev-push.service`
- [ ] Manual push succeeds: `bash .../dev-node-nas-push.sh push` exits 0

### ✅ Overall Integration

- [ ] Worker pulls from NAS every 30 minutes (immutable source)
- [ ] Dev can push configs on demand (git integration works)
- [ ] Health checks run every 15 minutes automatically
- [ ] No manual intervention required
- [ ] All credentials from GSM (never on disk)
- [ ] Audit trail logged to `/opt/nas-sync/audit/`

---

## TROUBLESHOOTING

### Issue: SSH Connection Refused

**Solution**:
```bash
# Verify SSH key exists
ls -la ~/.ssh/id_ed25519

# Test SSH connection with verbose output
ssh -v automation@192.168.168.42

# Check if SSH service running on target
ssh automation@192.168.168.42 sudo systemctl status ssh
```

### Issue: Permission Denied Creating `/opt` directories

**Solution**:
```bash
# Verify you're logged in as 'automation' user
whoami

# Create with more restricted permissions
mkdir -p /opt/automation
chmod 700 /opt/automation

# Then use sudo for /etc/systemd
sudo mkdir -p /opt/nas-sync
```

### Issue: Sync Files Not Appearing

**Solution**:
```bash
# Check if NAS is actually reachable
ping 192.168.168.100

# Verify SSH key authentication works
ssh -i ~/.ssh/id_ed25519 automation@192.168.168.100 ls /eiq-nas

# Check last sync logs
sudo journalctl -u nas-worker-sync.service -p err

# Run sync manually for debugging
bash /opt/automation/scripts/worker-node-nas-sync.sh --verbose
```

### Issue: Systemd Timers Not Running

**Solution**:
```bash
# Verify timer is enabled
sudo systemctl is-enabled nas-worker-sync.timer

# Start manually if needed
sudo systemctl start nas-worker-sync.timer

# Check timer details
sudo systemctl list-timers nas-worker-sync.timer

# Re-enable if disabled
sudo systemctl enable --now nas-worker-sync.timer
```

---

## AUTOMATION OVERVIEW

Once deployed, the system operates automatically:

| Component | Schedule | Action |
|-----------|----------|--------|
| **Worker Sync** | Every 30 min | Pulls IAC from NAS, validates, records audit |
| **Health Check** | Every 15 min | Validates sync health, connectivity, permissions |
| **Dev Push** | On demand | Pushes configs to NAS, validates YAML |
| **Monitoring** | Continuous | Prometheus collects metrics, fires alerts |
| **Audit Trail** | Every operation | JSON Lines append-only log |

### Manual Operations (Optional)

```bash
# Force immediate sync (instead of waiting 30 min)
bash /opt/automation/scripts/worker-node-nas-sync.sh

# Force immediate health check
bash /opt/automation/scripts/healthcheck-worker-nas.sh

# Manual push from dev node
bash /opt/automation/scripts/dev-node-nas-push.sh push

# Watch mode (continuous push on changes)
bash /opt/automation/scripts/dev-node-nas-push.sh watch
```

---

## PRODUCTION VERIFICATION (24-HOUR)

After 24 hours, verify:

1. **Sync History**: `tail -20 /opt/nas-sync/audit/audit.jsonl`
   - Should show ~48 successful syncs (one every 30 min)

2. **File Consistency**: 
   - On worker: `find /opt/nas-sync/iac -type f | wc -l`
   - On NAS: `find /eiq-nas -type f | wc -l`
   - Should be equal (immutability verified)

3. **Zero Manual Intervention**: No manual commands run except initial deployment

4. **All Constraints Met**:
   - ✅ Immutable: All configs pulled from NAS
   - ✅ Ephemeral: Can restart worker anytime
   - ✅ Idempotent: Sync runs 48x in 24h without issues
   - ✅ No-Ops: No manual intervention required
   - ✅ GSM Vault: All credentials from Secret Manager
   - ✅ Direct Deploy: No GitHub Actions used

---

## CLEANUP (If Needed)

To completely remove NAS integration:

```bash
# On worker node
sudo systemctl stop nas-integration.target
sudo systemctl disable nas-integration.target
sudo rm /etc/systemd/system/nas-*.* /etc/systemd/system/nas-integration.target
sudo systemctl daemon-reload

# Remove directories
rm -rf /opt/nas-sync /opt/automation/scripts

# On dev node
sudo systemctl stop nas-dev-push.service
sudo systemctl disable nas-dev-push.service
sudo rm /etc/systemd/system/nas-dev-push.*
sudo systemctl daemon-reload

# Remove directories
rm -rf /opt/automation/scripts
```

---

## SUPPORT

- **Quick Reference**: [NAS_QUICKSTART.md](./docs/NAS_QUICKSTART.md)
- **Complete Guide**: [NAS_INTEGRATION_COMPLETE.md](./docs/NAS_INTEGRATION_COMPLETE.md)
- **Architecture**: [ARCHITECTURE_OPERATIONAL.md](./ARCHITECTURE_OPERATIONAL.md)
- **Issues**: [GitHub Issue #3156](https://github.com/kushin77/self-hosted-runner/issues/3156)

---

## DEPLOYMENT RECORD

**Deployment Date**: [To be filled: March 14, 2026 or later]  
**Deployed By**: [To be filled: username]  
**Git Commits**: 0305dab44, c2b40c444  
**Verification Status**: [To be filled: VERIFIED or PENDING]  
**Completion Time**: [To be filled: actual execution time]

Record this in GitHub issue #3156 for immutable audit trail.
