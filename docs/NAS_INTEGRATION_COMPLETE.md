# 🗄️ NAS Server On-Premises Integration Guide

**Complete setup for worker node (192.168.168.42) and dev node (192.168.168.31)**

**Date**: March 14, 2026  
**Status**: 🟢 Production Ready  
**Version**: 1.0

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Worker Node Setup](#worker-node-setup)
4. [Dev Node Setup](#dev-node-setup)
5. [Systemd Integration](#systemd-integration)
6. [Health Monitoring](#health-monitoring)
7. [Troubleshooting](#troubleshooting)
8. [Operations](#operations)

---

## Architecture Overview

### Design Pattern

```
┌──────────────────────────────────────────────────────────────┐
│                    GitHub Repository                         │
│              (Source of Truth for Code)                       │
└──────────────────────┬───────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
   ┌─────────────┐          ┌─────────────────┐
   │ Dev Node    │          │ NAS Repository  │
   │ (.31)       │  ─push──►│ (.100)          │
   ├─────────────┤          ├─────────────────┤
   │ Git Repo    │◄─sync─── │ Canonical IAC   │
   │ IDE/Editor  │          │ GSM Credentials │
   │ Local Tests │          │ Config Vault    │
   └─────────────┘          └────────┬────────┘
                                     │
                                     │ pull (rsync)
                                     │ every 30 min
                                     ▼
                            ┌─────────────────┐
                            │ Worker Node     │
                            │ (.42)           │
                            ├─────────────────┤
                            │ /opt/nas-sync/  │
                            │  ├─ iac/        │
                            │  ├─ configs/    │
                            │  ├─ credentials/│
                            │  └─ audit/      │
                            └─────────────────┘
```

### Synchronization Flow

| Component | Source | Destination | Method | Frequency | Purpose |
|-----------|--------|-------------|--------|-----------|---------|
| **IAC Config** | Dev Node → NAS → Worker Node | Rsync over SSH | Rsync | Every 30 min | Infrastructure definitions |
| **Credentials** | GSM (via NAS) | Worker Node | SSH fetch | Every 30 min | Service account keys |
| **Push Events** | Dev Node → NAS | Direct rsync | Rsync/Git | Manual + watch | Configuration updates |
| **Health Status** | Worker Node → Logging | Journal/File | Local | Every 15 min | Monitoring & alerts |

---

## Prerequisites

### System Requirements

**All Nodes:**
- SSH client/server with Ed25519 key support
- `rsync` installed (≥3.1.3)
- `jq` for JSON processing
- Bash 4.0+

**Worker Node (192.168.168.42):**
- 10GB free space in `/opt`
- User `automation` with sudo access
- SSH key at `/home/automation/.ssh/id_ed25519` (or configured)
- Network access to NAS (192.168.168.100:22)

**Dev Node (192.168.168.31):**
- Git installed
- `/opt/iac-configs` directory writable by automation user
- Network access to NAS
- (Optional) `yamllint` for configuration validation

**NAS Server (192.168.168.100):**
- Service account `svc-nas` with SSH access
- GCP Secret Manager access (for credential distribution)
- Repositories at:
  - `/home/svc-nas/repositories/iac` (canonical IAC)
  - `/home/svc-nas/config-vault` (encrypted configs)

### Network Requirements

- All nodes can reach each other on port 22 (SSH)
- NAS can be reached from both worker and dev nodes
- Firewall allows SSH key-based authentication

---

## Worker Node Setup

### Step 1: SSH Key Configuration

Worker node needs SSH key to access NAS:

```bash
# On worker node (192.168.168.42)
sudo mkdir -p /home/automation/.ssh
sudo ssh-keygen -t ed25519 -f /home/automation/.ssh/id_ed25519 -N '' -C 'worker-nas-sync'
sudo chown automation:automation /home/automation/.ssh/id_ed25519*
sudo chmod 600 /home/automation/.ssh/id_ed25519
sudo chmod 644 /home/automation/.ssh/id_ed25519.pub

# Add NAS to known_hosts
ssh-keyscan -t ed25519 192.168.168.100 >> /etc/ssh/ssh_known_hosts 2>/dev/null
```

### Step 2: Register SSH Key on NAS

Share public key with NAS administrator:

```bash
# On worker node - get public key content
sudo cat /home/automation/.ssh/id_ed25519.pub

# NAS administrator adds to /home/svc-nas/.ssh/authorized_keys
# ssh-rsa AAAAB3NzaC1... automation@worker-node
```

### Step 3: Deploy Sync Scripts

```bash
# Copy scripts to worker node
scp -r scripts/nas-integration automation@192.168.168.42:/opt/automation/scripts/

# Make executable
ssh automation@192.168.168.42 "chmod 755 /opt/automation/scripts/nas-integration/*.sh"

# Create working directories
ssh automation@192.168.168.42 "mkdir -p /opt/nas-sync/{iac,configs,credentials,audit}"
```

### Step 4: Test Initial Sync

```bash
# On worker node, run initial sync manually
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Expected output:
# ✅ SSH key found
# ✅ NAS connectivity verified
# ✅ Sync directories initialized
# ✅ IAC sync complete
# ✅ Configuration sync complete
# ✅ Credentials fetched
# ✅ Sync integrity validated
# ✅ Health check complete
```

### Step 5: Install Systemd Services

```bash
# Copy systemd files
sudo cp systemd/nas-*.{service,timer} /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable nas-integration.target
sudo systemctl enable nas-worker-sync.timer
sudo systemctl enable nas-worker-healthcheck.timer

# Start services
sudo systemctl start nas-integration.target

# Verify
sudo systemctl status nas-worker-sync.timer
sudo systemctl status nas-worker-healthcheck.timer
```

---

## Dev Node Setup

### Step 1: SSH Key Configuration (Same as Worker)

```bash
sudo mkdir -p /home/automation/.ssh
sudo ssh-keygen -t ed25519 -f /home/automation/.ssh/id_ed25519 -N '' -C 'dev-nas-push'
sudo chown automation:automation /home/automation/.ssh/id_ed25519*
ssh-keyscan -t ed25519 192.168.168.100 >> /etc/ssh/ssh_known_hosts
```

### Step 2: Setup IAC Configuration Directory

```bash
# Create and populate IAC configs directory
sudo mkdir -p /opt/iac-configs
sudo chown automation:automation /opt/iac-configs
cd /opt/iac-configs

# Copy your infrastructure code, manifests, etc.
git clone https://github.com/kushin77/self-hosted-runner.git . 2>/dev/null || true

# Verify structure
ls -la /opt/iac-configs/
# Should contain: terraform/, kubernetes/, docker/, configs/, etc.
```

### Step 3: Deploy Push Script

```bash
# Copy script
scp -r scripts/nas-integration/dev-node-nas-push.sh automation@192.168.168.31:/opt/automation/scripts/nas-integration/
chmod 755 /opt/automation/scripts/nas-integration/dev-node-nas-push.sh
```

### Step 4: Test Push Operation

```bash
# On dev node - do a test push
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push

# Expected output:
# ✅ Environment validation passed
# ✅ SSH key detected
# ✅ Staging directory prepared
# ✅ Content validation passed
# ✅ Push to NAS completed successfully
```

### Step 5: Enable Watch Mode (Optional)

For continuous synchronization:

```bash
# Start watch mode in background (or use systemd service)
ENABLE_GIT_COMMIT=true bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch &

# Or install as service:
sudo cp systemd/nas-dev-push.service /etc/systemd/system/
sudo systemctl enable nas-dev-push.service
sudo systemctl start nas-dev-push.service
```

---

## Systemd Integration

### Service Files Created

| File | Purpose | Runs | Frequency |
|------|---------|------|-----------|
| `nas-worker-sync.service` | Sync IAC to worker | worker node | Triggered by timer |
| `nas-worker-sync.timer` | Schedule worker sync | worker node | Every 30 minutes |
| `nas-worker-healthcheck.service` | Health checks | worker node | Triggered by timer |
| `nas-worker-healthcheck.timer` | Schedule health checks | worker node | Every 15 minutes |
| `nas-dev-push.service` | Push configs from dev | dev node | Manual or watch |
| `nas-integration.target` | Aggregate target | both | Startup |

### Enable All Services

```bash
# On both nodes
sudo systemctl daemon-reload
sudo systemctl enable nas-integration.target
sudo systemctl start nas-integration.target

# Verify
sudo systemctl list-units | grep nas-
```

### View Service Logs

```bash
# Worker node sync logs
sudo journalctl -u nas-worker-sync.service -f

# Worker node health checks
sudo journalctl -u nas-worker-healthcheck.service -f

# Dev node push logs
sudo journalctl -u nas-dev-push.service -f
```

---

## Health Monitoring

### Automated Health Checks

Worker node runs health checks every 15 minutes:

```bash
# Manual health check
bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose

# Sample output:
# ✅ NAS connectivity OK
# ✅ Sync directories OK
# ✅ Last sync: 125s ago
# ✅ Sync integrity OK
# ✅ Disk usage OK: 35%
# ✅ Recent syncs: 8 (last 24h)
# 🟢 Overall Status: HEALTHY
```

### Health Check Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Last sync age | > 1 hour | > 2 hours |
| Disk usage | > 85% | > 95% |
| NAS connectivity | Unreachable | Unreachable |
| Audit trail | No entries | No entries (48h) |
| Directory permissions | Incorrect on credentials | Files world-readable |

### Logs Location

```
Worker Node: /var/log/nas-integration/
├── worker-health.log          # Health check results
├── nas-sync-*.log             # Sync operations
└── sync-audit-trail.jsonl     # JSON audit events

Dev Node: /var/log/nas-integration/
├── dev-node-push.log          # Push operations
└── dev-node-audit-trail.jsonl # Audit events
```

---

## Troubleshooting

### Issue: SSH Connection Fails

**Symptoms**: "Cannot connect to NAS" error

**Steps**:
```bash
# 1. Verify SSH key exists
ls -la /home/automation/.ssh/id_ed25519

# 2. Test NAS connectivity
ssh -i /home/automation/.ssh/id_ed25519 -v svc-nas@192.168.168.100

# 3. Check authorized_keys on NAS
# Ask NAS admin to verify your key is in authorized_keys

# 4. Check known_hosts
grep 192.168.168.100 /etc/ssh/ssh_known_hosts

# 5. Verify firewall allows port 22
ping -c 1 192.168.168.100
telnet 192.168.168.100 22
```

### Issue: Sync Stale (No Recent Sync)

**Symptoms**: "Last sync: 3600s ago" warning

**Steps**:
```bash
# 1. Run manual sync
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# 2. Check systemd timer status
sudo systemctl status nas-worker-sync.timer

# 3. View timer logs
sudo journalctl -u nas-worker-sync.timer -n 50

# 4. Force timer run
sudo systemctl start nas-worker-sync.service
```

### Issue: Disk Usage High

**Symptoms**: "Disk usage high: 92%"

**Steps**:
```bash
# 1. Check sync directory size
du -sh /opt/nas-sync

# 2. Clean old audit logs
cd /opt/nas-sync/audit
find . -name "*.log" -mtime +7 -delete

# 3. Verify no duplicate copies
find /opt/nas-sync -type f -duplicate -ls

# 4. Consider moving to larger partition
# Contact infrastructure team
```

### Issue: Permission Errors

**Symptoms**: "Permission denied" when accessing credentials

**Steps**:
```bash
# 1. Check directory permissions
ls -la /opt/nas-sync/credentials

# 2. Should be: drwx------ (700)
# 3. Fix if needed:
sudo chmod 700 /opt/nas-sync/credentials
sudo chown automation:automation /opt/nas-sync/credentials

# 4. Check file permissions
ls -la /opt/nas-sync/credentials/
# Should be: -rw------- (600) for all files
```

---

## Operations

### Manual Sync Operations

#### Force Full Sync (Worker Node)

```bash
# Run sync immediately
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Or via systemd
sudo systemctl start nas-worker-sync.service
```

#### Push Changes (Dev Node)

```bash
# One-time push
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push

# Show pending changes
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff

# Start continuous watch (will auto-push on changes)
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch
```

### Monitor Sync Status

```bash
# Worker node - see last sync
cat /opt/nas-sync/audit/.last-success

# View detailed audit trail
tail -f /opt/nas-sync/audit/sync-audit-trail.jsonl | jq '.'

# Dev node - view push history
tail -f /var/log/nas-integration/dev-node-push.log
```

### Verify Configuration Sync

```bash
# On worker node - check IAC is present
ls -la /opt/nas-sync/iac/
du -sh /opt/nas-sync/iac

# Validate configs parsed correctly
find /opt/nas-sync/configs -name "*.yaml" -o -name "*.json" | wc -l

# Check credentials are secure
ls -la /opt/nas-sync/credentials
stat /opt/nas-sync/credentials
```

### Rollback to Previous Configuration

```bash
# NAS maintains Git history
# On NAS, view available versions:
cd /home/svc-nas/repositories/iac
git log --oneline | head -10

# Checkout previous version
git checkout <commit-hash>

# Worker node will pull the reverted version on next sync (30 min)
# Or force immediate sync:
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh
```

---

## Monitoring & Alerts

### Prometheus Metrics

NAS health check automatically exports JSON metrics:

```bash
# View latest health status
cat /opt/nas-sync/audit/sync-audit-trail.jsonl | jq '.status' | sort | uniq -c
```

### Alert Rules

Recommended Prometheus alert rules in `/docker/prometheus/nas-alert-rules.yml`:

```yaml
- alert: NASWorkerSyncStale
  expr: time() - nas_last_sync_timestamp > 3600
  for: 15m

- alert: NASConnectivityDown
  expr: nas_connectivity_status == 0
  for: 5m

- alert: NASCredentialsFailed
  expr: nas_credentials_fetch_failed == 1
  for: 10m

- alert: NASHighDiskUsage
  expr: nas_disk_usage_percent > 85
  for: 10m
```

---

## Security Considerations

### SSH Key Management

- Ed25519 keys (stronger than RSA)
- 600 permissions on private keys
- Regular rotation (every 90 days recommended)
- Separate keys per node (not shared)

### Credential Handling

- Credentials fetched from GSM, never stored on disk
- Temporary files shredded after use
- Audit trail immutable and append-only
- No credentials in logs or Git history

### Access Control

- Least privilege SSH access (svc-nas user only)
- StrictHostKeyChecking enabled
- Separate service account per node
- SSH known_hosts maintained centrally

---

## Performance Tuning

### Optimize Sync Interval

Current default: 30 minutes (worker) and 15 minutes (health)

To adjust:

```bash
# Edit timer file
sudo systemctl edit nas-worker-sync.timer

# Modify OnUnitActiveSec
[Timer]
OnUnitActiveSec=15min    # Change from 30min

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart nas-worker-sync.timer
```

### Network Optimization

For high-latency networks, adjust rsync options in sync script:

```bash
# Edit worker-node-nas-sync.sh
RSYNC_OPTS="-avz --checksum --timeout=60 --bwlimit=10000"
                                            # ^^^^^^ limit to 10MB/s
```

---

## Maintenance

### Weekly Tasks

- [ ] Review health check logs for warnings
- [ ] Verify sync timestamps in audit trail
- [ ] Check disk usage trends

### Monthly Tasks

- [ ] Review SSH key access logs
- [ ] Audit Git commit history on NAS
- [ ] Clean old audit log files older than 90 days

### Quarterly Tasks

- [ ] Rotate SSH keys (generate new keys, update authorized_keys)
- [ ] Review and update credential rotation policies
- [ ] Capacity planning based on usage trends

---

## Support & Escalation

### Issue: Persistent Connectivity Problems

Contact NAS administrator for:
- Network connectivity verification
- SSH service status check
- Repository accessibility from your node

### Issue: Credential Fetch Failures

Contact GSM administrator for:
- GCP service account permissions
- Secret Manager API access
- Secret versioning status

### Audit & Compliance

Access audit trail for compliance reviews:

```bash
# Export audit events for period
jq 'select(.timestamp > "2026-03-01" and .timestamp < "2026-03-15")' \
   /opt/nas-sync/audit/sync-audit-trail.jsonl > compliance-report.jsonl

# Generate summary
jq -s 'group_by(.status) | map({status: .[0].status, count: length})' \
   compliance-report.jsonl
```

---

**Last Updated**: March 14, 2026  
**Next Review**: June 14, 2026  
**Owner**: Infrastructure Team  
**Status**: 🟢 PRODUCTION
