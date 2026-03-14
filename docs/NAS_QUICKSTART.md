# 🚀 NAS Integration Quick Start

**5-Minute Setup to Enable NAS Sync on Worker & Dev Nodes**

## Prerequisites Checklist

- [ ] SSH access to both nodes (192.168.168.31 and 192.168.168.42)
- [ ] NAS reachable at 192.168.168.100:22
- [ ] Public SSH key shared with NAS administrator

## Worker Node (192.168.168.42) - 3 Steps

### 1. Deploy Scripts & Services (2 minutes)

```bash
# SSH to worker node
ssh automation@192.168.168.42

# Create automation directory
sudo mkdir -p /opt/automation/scripts
cd /opt/automation

# Clone/copy scripts (from dev machine)
scp -r scripts/nas-integration automation@192.168.168.42:/opt/automation/

# Make executable
sudo chmod 755 /opt/automation/scripts/nas-integration/*.sh

# Create working directories
mkdir -p /opt/nas-sync/{iac,configs,credentials,audit}
```

### 2. Test Initial Sync (1 minute)

```bash
# Run sync manually
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Log output shows:
# ✅ SSH key found
# ✅ NAS connectivity verified
# ✅ IAC sync complete
```

### 3. Enable Systemd Automation (30 seconds)

```bash
# Copy systemd files
sudo cp systemd/nas-*.service systemd/nas-*.timer /etc/systemd/system/

# Enable & start
sudo systemctl daemon-reload
sudo systemctl enable nas-integration.target
sudo systemctl start nas-integration.target

# Verify running
sudo systemctl status nas-worker-sync.timer
# Active: active (waiting)
```

## Dev Node (192.168.168.31) - 3 Steps

### 1. Deploy Push Script (1 minute)

```bash
# SSH to dev node
ssh automation@192.168.168.31

# Copy script
mkdir -p /opt/automation/scripts/nas-integration
cp dev-node-nas-push.sh /opt/automation/scripts/nas-integration/
chmod 755 /opt/automation/scripts/nas-integration/dev-node-nas-push.sh
```

### 2. Test Push Operation (1 minute)

```bash
# Test push to NAS
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push

# Shows:
# ✅ SSH key detected
# ✅ Staging directory prepared
# ✅ Push to NAS completed successfully
```

### 3. Verify Configuration Received

```bash
# On worker node, verify configs arrived
ls /opt/nas-sync/iac
du -sh /opt/nas-sync/iac

# Should show files synced from dev node
```

## Verification (All Done!)

### Confirm Worker Node Syncing

```bash
# Check last sync time
cat /opt/nas-sync/audit/.last-success

# Check sync logs
tail -20 /var/log/nas-integration/worker-health.log

# Expected: ✅ All healthy
```

### Monitor Live Sync

```bash
# Watch for next automatic sync (30 min)
watch -n 5 'cat /opt/nas-sync/audit/.last-success | date -f - "+%s ago"'

# Or check timer status
sudo systemctl status nas-worker-sync.timer
```

## Next: Continuous Monitoring

```bash
# View health dashboard
bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose

# Enable dev node watch mode (auto-push on changes)
nohup bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch > /tmp/nas-watch.log 2>&1 &
```

## Troubleshooting 1-Liners

```bash
# Test NAS connectivity
ssh -i ~/.ssh/id_ed25519 svc-nas@192.168.168.100 echo "OK"

# Check last sync failure details
tail -100 /opt/nas-sync/audit/sync-audit-trail.jsonl | jq '.[] | select(.status != "SUCCESS")'

# Force immediate sync
sudo systemctl start nas-worker-sync.service

# View systemd service logs
sudo journalctl -u nas-worker-sync.service -n 50
```

---

**Total Time**: ~5 minutes  
**Status**: Ready for production monitoring  

Next: See [NAS_INTEGRATION_COMPLETE.md](../docs/NAS_INTEGRATION_COMPLETE.md) for advanced configuration
