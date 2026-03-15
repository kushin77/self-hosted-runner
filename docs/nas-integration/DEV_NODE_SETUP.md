# Dev Node (192.168.168.31) NAS Integration - Complete Guide

**Date**: March 15, 2026  
**Status**: 🟢 Ready for Deployment  
**Target**: Development Workstation (192.168.168.31)  
**NAS Server**: 192.168.168.100  
**Worker Node**: 192.168.168.42  

---

## Executive Summary

The development node (192.168.168.31) is now configured to leverage the NAS (192.168.168.100) as a centralized Infrastructure-as-Code (IaC) repository. This enables:

✅ **Centralized Configuration Management** - Single source of truth for all infrastructure  
✅ **Efficient Propagation** - Changes automatically propagate to worker nodes  
✅ **Immutable Audit Trail** - All syncs are logged and audited  
✅ **Zero Manual Intervention** - Fully automated push/pull mechanisms  
✅ **Multi-node Scaling** - Support for multiple worker nodes  
✅ **Version Control** - Optional Git integration for change tracking  

---

## Architecture Overview

### Network Topology

```
Developer Workstation          NAS Server              Production Worker
192.168.168.31                192.168.168.100         192.168.168.42
┌──────────────────┐         ┌─────────────────┐      ┌──────────────┐
│  /opt/iac-configs│ ─rsync→ │ /repositories/  │ ←rsync──│ /opt/nas-sync│
│   Your edits     │ (push)  │ /config-vault/  │ (pull)  │ Auto-deploys │
│                  │         │ GSM credentials │ (30min) │              │
└──────────────────┘         └─────────────────┘         └──────────────┘
        │                           │                           │
        └─────GET STATUS────────────┼──────────────────────────┘
        
       GCP Secret Manager (ED25519 keys, service account creds)
```

### Data Flow (Detailed)

```
1. EDIT PHASE (Your Machine)
   /opt/iac-configs/*.yaml
   /opt/iac-configs/terraform/
   /opt/iac-configs/kubernetes/
   
2. PUSH PHASE (On-demand)
   bash dev-node-nas-push.sh push
   ├─ Validate configs (YAML/JSON)
   ├─ Check for sensitive files (*.key, password*, etc)
   ├─ Create staging area
   ├─ Verify NAS connectivity
   └─ Rsync to NAS with checksums
   
3. RELAY PHASE (Automatic - NAS)
   NAS stores as canonical source:
   /home/svc-nas/repositories/iac/
   /home/svc-nas/config-vault/
   
4. PULL PHASE (Every 30 minutes - Worker)
   Worker detects NAS updates
   ├─ Verify file integrity
   ├─ Fetch credentials from GSM
   ├─ Apply configurations (kubectl, terraform, ansible)
   └─ Log results to audit trail

5. AUDIT PHASE (Continuous)
   All operations logged:
   /var/log/nas-integration/dev-node-push.log
   /var/audit/nas-integration/
```

---

## Installation & Setup

### Prerequisites

Before starting, ensure:

- ✅ Dev node is at 192.168.168.31
- ✅ NAS server is at 192.168.168.100 (fully configured)
- ✅ SSH access available (port 22)
- ✅ Rsync installed on dev node
- ✅ ~10GB free disk space
- ✅ User has sudo access

### Step 1: Initial Setup

Run the comprehensive setup script:

```bash
# SSH into dev node or run locally if on .31
cd /home/akushnir/self-hosted-runner

# Run setup (requires sudo)
sudo bash scripts/nas-integration/setup-dev-node.sh
```

**What this does:**
- Creates `automation` service account
- Generates ED25519 SSH key for NAS auth
- Creates local directories (`/opt/iac-configs/`, `/var/log/nas-integration/`)
- Installs scripts and documentation
- Configures systemd services
- Creates environment configuration

**Output includes:**
- SSH public key (needed for NAS admin)
- Quick start guide
- Key directory locations
- Command reference

### Step 2: Add SSH Key to NAS

The setup script will provide a public key. Send it to NAS admin:

```bash
# Display your public key
cat /home/automation/.ssh/nas-push-key.pub

# Output should look like:
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ... nas-push@192.168.168.31
```

The NAS admin adds this to:
```
/home/svc-nas/.ssh/authorized_keys
```

Then test connectivity:

```bash
ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100 "echo OK"
# Output: OK
```

### Step 3: Verify Connectivity

```bash
bash scripts/nas-integration/dev-node-automation.sh connectivity
```

Expected output:
```
✅ Connected to NAS successfully
```

---

## Daily Operations

### Operation 1: Push Configurations to NAS

For one-time push of changes:

```bash
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push
```

**What happens:**
- Validates all configurations (YAML/JSON)
- Blocks sensitive files (*.key, *password*, etc)
- Compares with NAS using checksums
- Transfers only changed files (efficient)
- Creates audit trail entry
- Logs all operations

**Example output:**
```
[2026-03-15 14:30:45] INFO: Validating dev node environment...
[2026-03-15 14:30:46] ✅ Environment validation passed
[2026-03-15 14:30:47] INFO: Preparing staging directory...
[2026-03-15 14:30:48] INFO: Detecting pending changes...
[2026-03-15 14:31:02] INFO: Pushing configurations to NAS...
[2026-03-15 14:31:15] ✅ Push to NAS completed successfully
```

### Operation 2: Watch Mode (Continuous Sync)

For continuous automatic sync as you edit:

```bash
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch
```

**Features:**
- Monitors `/opt/iac-configs/` for changes
- Auto-pushes when files are saved
- Runs in foreground (press Ctrl+C to stop)
- Perfect for development workflow

### Operation 3: Check Pending Changes

Before pushing, see what changed:

```bash
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff
```

**Output example:**
```
modified: terraform/vpc.tf
added: kubernetes/deployment.yaml
deleted: ansible/deprecated.yaml
```

### Operation 4: Monitor Integration Status

Check health and status:

```bash
bash scripts/nas-integration/dev-node-automation.sh status
```

**Shows:**
- Environment variables
- SSH key status and fingerprint
- Directory accessibility
- Active systemd services
- Recent sync status

### Operation 5: View Logs

Monitor what's happening:

```bash
# View last 50 lines
tail -n 50 /var/log/nas-integration/dev-node-push.log

# Follow logs in real-time
tail -f /var/log/nas-integration/dev-node-push.log

# Via systemd journal
journalctl -u nas-dev-push.service -f
```

### Operation 6: Health Check

Verify system health:

```bash
bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose
```

**Checks:**
- NAS connectivity
- Directory structure integrity
- Last sync timestamp
- File permissions
- Disk usage
- Audit trail status

### Operation 7: Resolve Issues

If something fails:

```bash
# Test NAS connectivity directly
ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100 "ls /home/svc-nas/repositories/iac"

# Check disk space
df -h /opt/iac-configs

# Review error logs
grep ERROR /var/log/nas-integration/dev-node-push.log

# Manual rsync test
rsync -avz /opt/iac-configs/ \
  -e "ssh -i /home/automation/.ssh/nas-push-key" \
  svc-nas@192.168.168.100:/home/svc-nas/repositories/iac/ --dry-run
```

---

## Configuration

### Environment Variables

Located at: `/opt/automation/dev-node-nas.env`

Key variables:

```bash
# NAS Network
NAS_HOST="192.168.168.100"          # NAS server IP
NAS_PORT="22"                       # SSH port
NAS_USER="svc-nas"                  # NAS SSH user

# Local Paths
OPT_AUTOMATION="/opt/automation"    # Base automation directory
OPT_IAC="/opt/iac-configs"          # Local IAC repo
NAS_PUSH_STAGING="/tmp/nas-push-staging"  # Temp staging

# Logging
LOG_DIR="/var/log/nas-integration"
AUDIT_DIR="/var/audit/nas-integration"
```

### SSH Configuration

**Key Location**: `/home/automation/.ssh/nas-push-key`

**Key Type**: ED25519 (preferred for this use case)

**Permissions**: 600 (read/write for owner only)

**Regenerate if needed**:

```bash
sudo ssh-keygen -t ed25519 \
  -f /home/automation/.ssh/nas-push-key \
  -N "" -C "nas-push@192.168.168.31"

# Then share new public key with NAS admin
cat /home/automation/.ssh/nas-push-key.pub
```

### Rsync Options

Current config uses:
```bash
-avz --checksum --timeout=30 --delete
```

- `a` - Archive mode (preserve permissions)
- `v` - Verbose
- `z` - Compress during transfer
- `--checksum` - Verify with checksums (not just timestamps)
- `--timeout=30` - 30-second timeout per file
- `--delete` - Remove files on dest that aren't on source

---

## Integration Points

### With Worker Nodes

Worker nodes pull from NAS every 30 minutes:

```bash
# On worker (192.168.168.42)
sudo systemctl status nas-worker-sync.timer
sudo systemctl list-timers nas-worker-sync.timer

# View worker sync logs
sudo tail -f /var/log/nas-integration/worker-sync.log
```

Changes appear on worker within 30 minutes:

```bash
# Typical timeline:
10:00 AM - You push to NAS
10:00 AM - Audit trail recorded
10:30 AM - Worker pulls and updates
10:31 AM - Deployment begins (if using auto-deploy)
10:35 AM - Changes live in production
```

### With Git/GitHub

Optional: Commit changes to GitHub alongside NAS push:

```bash
# Enable in config
export ENABLE_GIT_COMMIT="true"

# Then push includes git commit
bash dev-node-nas-push.sh push
```

Configuration in script:
```bash
ENABLE_GIT_COMMIT="false"  # Set to true to enable
GIT_REPO="https://github/kushin77/self-hosted-runner"
```

### With Monitoring

Prometheus monitoring for NAS integration:

```bash
# View alerts (if Prometheus configured)
# http://prometheus:9090 → Search: nas_

# Key metrics:
# - nas_dev_push_success_total
# - nas_dev_push_duration_seconds
# - nas_sync_interval
# - nas_connectivity_status
```

---

## Troubleshooting

### Issue 1: SSH Key Not Found

**Symptom**: `SSH key not found` error when pushing

**Solution**:
```bash
# Check key exists
ls -la /home/automation/.ssh/nas-push-key

# If missing, regenerate
sudo bash setup-dev-node.sh
# Then add new public key to NAS admin
```

### Issue 2: Cannot Connect to NAS

**Symptom**: `Cannot reach NAS repository` error

**Steps**:
1. Check network connectivity:
   ```bash
   ping -c 3 192.168.168.100
   ```

2. Check SSH:
   ```bash
   ssh -vvv -i /home/automation/.ssh/nas-push-key \
     svc-nas@192.168.168.100 "echo OK"
   ```

3. Verify NAS has your public key:
   ```bash
   # On NAS admin's machine
   grep "nas-push@192.168.168.31" /home/svc-nas/.ssh/authorized_keys
   ```

4. Check SSH daemon on NAS:
   ```bash
   # On NAS
   sudo systemctl status ssh
   ```

### Issue 3: Files Not Syncing to Worker

**Symptom**: Changes pushed to NAS but not appearing on worker

**Steps**:

1. Verify push succeeded:
   ```bash
   grep "completed successfully" /var/log/nas-integration/dev-node-push.log | tail -1
   ```

2. Check files on NAS:
   ```bash
   ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100 \
     "ls -la /home/svc-nas/repositories/iac/ | head -20"
   ```

3. Wait for worker to pull (30-minute interval):
   ```bash
   # Check when worker last synced
   ssh automation@192.168.168.42 \
     "tail /var/log/nas-integration/worker-sync.log"
   ```

4. Manual worker sync (if urgent):
   ```bash
   # On worker
   sudo /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh
   ```

### Issue 4: Permission Denied

**Symptom**: `Permission denied (publickey)` error

**Solution**:
1. Verify SSH key is readable:
   ```bash
   ls -la /home/automation/.ssh/nas-push-key
   # Should be: -rw------- automation automation
   ```

2. Fix if needed:
   ```bash
   chmod 600 /home/automation/.ssh/nas-push-key
   # And public key should be readable
   chmod 644 /home/automation/.ssh/nas-push-key.pub
   ```

### Issue 5: Sensitive Files Blocked

**Symptom**: `Found sensitive files matching pattern: *.key`

**Solution**:
Remove sensitive files before pushing:
```bash
# Find and remove
find /opt/iac-configs -name "*.key" -delete
find /opt/iac-configs -name "*secret*" -delete
find /opt/iac-configs -name "*password*" -delete

# Or move to .gitignore
echo "*.key" >> /opt/iac-configs/.gitignore
```

Sensitive files should come from GSM/Vault, not git/NAS.

### Issue 6: Rsync Timeout

**Symptom**: `rsync operation timed out` or transfer hangs

**Solution**:

1. Check network stability:
   ```bash
   ping -c 100 192.168.168.100 | grep -E "min|avg|max"
   ```

2. Try manual rsync with verbose:
   ```bash
   rsync -avvz \
     -e "ssh -i /home/automation/.ssh/nas-push-key" \
     /opt/iac-configs/ \
     svc-nas@192.168.168.100:/home/svc-nas/repositories/iac/ \
     --dry-run 2>&1 | tail -50
   ```

3. Increase timeout in config:
   ```bash
   # Edit dev-node-nas.env
   export RSYNC_OPTS="-avz --checksum --timeout=60"  # Increased from 30
   ```

---

## Security Considerations

### SSH Keys

✅ **What We Do Right:**
- ED25519 keys (modern, efficient)
- No passphrase (for automation)
- Restricted to NAS connectivity only
- Separate key from system default

⚠️ **What You Must Do:**
- Keep `/home/automation/.ssh/nas-push-key` secure
- Don't commit to git/share
- Rotate annually
- Monitor access logs

### Sensitive Files

✅ **Automatic Blocking:**
- `*.key`, `*.pem` files
- `*secret*` files
- `*password*` files
- `*credentials*` files

⚠️ **What You Must Do:**
- Use GSM/Vault for actual credentials
- Never store secrets in IaC repo
- Review blocking patterns in `dev-node-nas-push.sh`

### Audit Trail

All operations logged to:
- `/var/log/nas-integration/dev-node-push.log` (structured logs)
- `/var/audit/nas-integration/` (immutable audit trail)
- `journalctl -u nas-dev-push.service` (systemd journal)

### Network Security

- SSH only (no rsync over plain HTTP)
- Checksum verification (prevents tampering)
- Connection timeouts (prevent hanging)
- StrictHostKeyChecking enabled

---

## Advanced Usage

### 1. Batch Updates

Push multiple times:

```bash
# Update multiple systems
bash dev-node-nas-push.sh push

# Update again after changes
bash dev-node-nas-push.sh push

# All idempotent - safe to repeat
```

### 2. Selective Sync

Sync only specific directories:

```bash
# Manual rsync of just terraform
rsync -avz /opt/iac-configs/terraform/ \
  -e "ssh -i /home/automation/.ssh/nas-push-key" \
  svc-nas@192.168.168.100:/home/svc-nas/repositories/iac/terraform/
```

### 3. Automated Scheduling

Via cron (if manual scheduling preferred over systemd):

```bash
# Edit crontab
crontab -e

# Add: Push every 6 hours
0 */6 * * * /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push >> /var/log/nas-integration/cron-push.log 2>&1
```

### 4. Integration with CI/CD

Trigger from your CI system:

```bash
# From GitHub Actions, GitLab CI, etc
curl -X POST http://dev-node-webhook:8080/push \
  -H "Authorization: Bearer $TOKEN"
```

### 5. Custom Validation

Add your own validation:

```bash
# Edit dev-node-nas-push.sh
# Add to validate_push_content() function:

# Example: Check Kubernetes manifests
if command -v kubeval &>/dev/null; then
  find "$DEV_STAGING_DIR" -name "*.yaml" | xargs kubeval
fi
```

---

## Reference

### Quick Commands

```bash
# Show help
bash /opt/automation/scripts/nas-integration/dev-node-automation.sh help

# Full setup
sudo bash /opt/automation/scripts/nas-integration/setup-dev-node.sh

# Push to NAS
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push

# Watch for changes
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch

# Show changes
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff

# Health check
sudo bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh

# Test connectivity
bash /opt/automation/scripts/nas-integration/dev-node-automation.sh connectivity

# View logs
tail -f /var/log/nas-integration/dev-node-push.log

# Check status
bash /opt/automation/scripts/nas-integration/dev-node-automation.sh status
```

### Key Files & Locations

```
/home/automation/.ssh/nas-push-key          - SSH private key
/home/automation/.ssh/nas-push-key.pub      - SSH public key
/opt/automation/scripts/nas-integration/    - All integration scripts
/opt/automation/dev-node-nas.env            - Configuration file
/opt/iac-configs/                           - Your IaC repository (local)
/var/log/nas-integration/                   - Integration logs
/var/audit/nas-integration/                 - Audit trail
/opt/automation/DEV_NODE_QUICKSTART.md      - Quick reference
```

### Environment Variables

```bash
NAS_HOST                    - NAS server IP (192.168.168.100)
NAS_PORT                    - SSH port (22)
NAS_USER                    - NAS SSH user (svc-nas)
DEV_USER                    - Local automation user
OPT_AUTOMATION              - Base automation dir (/opt/automation)
OPT_IAC                     - Local IaC dir (/opt/iac-configs)
LOG_DIR                     - Logs directory
ENABLE_GIT_COMMIT           - Enable GitHub commits
SSH_KEY                     - SSH key path for NAS auth
```

### Error Codes

```
0   - Success
1   - SSH key not found
2   - NAS unreachable
3   - Validation failed (sensitive files, YAML errors)
4   - Rsync transfer failed
5   - Directory not found
6   - Permission denied
```

---

## Next Steps

1. **Setup**: Run `sudo bash scripts/nas-integration/setup-dev-node.sh`
2. **Share Key**: Send public key to NAS admin
3. **Test**: Run `bash scripts/nas-integration/dev-node-automation.sh connectivity`
4. **Populate**: Add your IaC to `/opt/iac-configs/`
5. **Push**: Run `bash scripts/nas-integration/dev-node-nas-push.sh push`
6. **Monitor**: Check `/var/log/nas-integration/dev-node-push.log`
7. **Wait**: Worker nodes pull every 30 minutes
8. **Verify**: Changes appear on 192.168.168.42

---

## Support & Documentation

- **Quick Start**: `/opt/automation/DEV_NODE_QUICKSTART.md` (5 min)
- **This Guide**: `/opt/automation/docs/nas-integration/DEV_NODE_SETUP.md` (comprehensive)
- **Full NAS Guide**: `/opt/automation/docs/nas-integration/NAS_INTEGRATION_COMPLETE.md` (all details)
- **Troubleshooting**: See "Troubleshooting" section above

---

**Status**: ✅ Ready for Production  
**Last Updated**: March 15, 2026  
**Maintained By**: DevOps Team
