# Phase 3 Deployment: Service Account Execution Guide

**Date:** March 15, 2026  
**Constraint Enforced:** Service account only (no sudo escalation)  
**Purpose:** Ensure all deployments run with minimal privileges  

---

## Overview

Phase 3 deployment **must be executed as the `automation` service account**, not as a regular user or root. This enforces the zero-ops, hands-off deployment model with proper security boundaries.

---

## Service Account Setup (One-Time)

### Create Service Account (if not exists)

```bash
# Create system service account
sudo useradd -r -s /bin/bash -d /home/automation -m automation

# Verify creation
id automation
# uid=1001(automation) gid=1001(automation) groups=1001(automation)
```

### Grant Deployment Access

```bash
# Allow automation to access deployment scripts
sudo chown -R automation:automation /home/akushnir/self-hosted-runner/scripts/redeploy
sudo chown -R automation:automation /home/akushnir/self-hosted-runner/logs

# Set permissions
sudo chmod 755 /home/akushnir/self-hosted-runner/scripts/redeploy
sudo chmod 755 /home/akushnir/self-hosted-runner/logs
```

---

## Execution Methods

### Method 1: Service Account Wrapper (Recommended)

```bash
bash scripts/redeploy/phase3-deployment-exec.sh
```

**What it does:**
- ✅ Verifies `automation` service account exists
- ✅ Detects current user context
- ✅ Switches to `automation` automatically (no sudo)
- ✅ Executes phase3-deployment-trigger.sh as `automation`
- ✅ Returns proper exit codes

**Advantages:**
- Automatic user context detection
- No sudo required
- Clean privilege boundary enforcement
- Production-ready error handling

---

### Method 2: Direct as Service Account

```bash
# Switch to automation account
su - automation

# Execute from within automation context
bash /home/akushnir/self-hosted-runner/scripts/redeploy/phase3-deployment-trigger.sh

# Exit automation context
exit
```

**Advantages:**
- Explicit user context
- Clear audit trail
- Manual control

---

### Method 3: SSH as Service Account (From Authorized Host)

```bash
# Execute remotely as automation
ssh automation@192.168.168.42 bash /home/akushnir/self-hosted-runner/scripts/redeploy/phase3-deployment-trigger.sh
```

**Advantages:**
- Remote execution
- Service account enforced at remote
- SSH audit trail for all operations

---

### Method 4: Systemd Service (Production Preferred)

```bash
# Install systemd service
sudo cp .systemd/phase3-deployment.service /etc/systemd/system/
sudo cp .systemd/phase3-deployment.timer /etc/systemd/system/

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable and start
sudo systemctl enable phase3-deployment.timer
sudo systemctl start phase3-deployment.service

# Verify
sudo systemctl status phase3-deployment.service
```

**Configuration:**
- **User:** automation (enforced in service file)
- **Schedule:** Daily 02:00 UTC (via timer)
- **Audit:** Immutable JSONL logs
- **Monitoring:** journalctl integration

**Advantages:**
- ✅ Fully automated daily execution
- ✅ Service account enforced by systemd
- ✅ Zero manual operations
- ✅ Complete audit trail via journalctl
- ✅ Rollback-safe (daemon manages lifecycle)

---

## Verification

### Verify Service Account Execution

```bash
# Check who is running deployment
ps aux | grep phase3-deployment

# Expected output shows automation user:
# automation 1234  0.0  0.1  12345  6789 ?  S  03:50  0:00 bash phase3-deployment-trigger.sh
```

### Monitor Execution

From authorized deployment host:

```bash
# Watch systemd logs in real-time
sudo journalctl -u phase3-deployment.service -f

# Check last 50 audit entries
tail -50 logs/phase3-deployment/audit-*.jsonl | jq '.user'
# Expected: All entries show "user": "automation"

# Verify immutable logs
tail -5 logs/phase3-deployment/audit-*.jsonl | jq '{timestamp, action, user}'
```

---

## Constraints Enforcement

### What This Ensures

| Constraint | Method | Enforcement |
|-----------|--------|------------|
| **No Sudo** | Service account only | No privilege escalation in deployment |
| **Service Account Only** | User context enforcement | All operations audit-logged to `automation` |
| **Immutable** | JSONL append-only | User field always matches `automation` |
| **Ephemeral** | Account permissions limited | Only access to necessary directories |
| **Idempotent** | No state persistence | Account resets per execution |
| **No Manual Ops** | Systemd automation | Zero interactive user involvement |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3 Deployment: Service Account Execution Model             │
└─────────────────────────────────────────────────────────────────┘

Execution Context:
  User: akushnir              ← Current user (any user)
        ↓
  Wrapper: phase3-deployment-exec.sh
        ↓
  Su: su - automation         ← Privilege boundary (no sudo)
        ↓
  Service Account: automation ← All deployment execution here
        ↓
  Deployment: phase3-deployment-trigger.sh
        ↓
  Execution: phase3-redeploy-100x.sh (as automation)
        ↓
  Audit: logs/phase3-deployment/audit-*.jsonl
         (all entries: "user": "automation")

Result: Zero privilege escalation, immutable audit trail
```

---

## Systemd Service Configuration

The `.systemd/phase3-deployment.service` file enforces service account:

```ini
[Service]
Type=oneshot
User=automation                    ← Enforces service account
WorkingDirectory=/home/akushnir/self-hosted-runner
ExecStart=/home/akushnir/self-hosted-runner/scripts/redeploy/phase3-deployment-trigger.sh
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true              ← Prevents privilege escalation
ProtectSystem=yes                 ← Restrict filesystem write access
ProtectHome=yes                   ← Restrict home directory access
PrivateTmp=yes                    ← Ephemeral temp directory
```

---

## Troubleshooting

### Issue: "User automation not found"

```bash
# Solution: Create service account
sudo useradd -r -s /bin/bash -d /home/automation -m automation
```

### Issue: "Permission denied" accessing script

```bash
# Solution: Grant automation access
sudo chown automation:automation /path/to/script
sudo chmod 755 /path/to/script
```

### Issue: Systemd service failing

```bash
# Check service status
sudo systemctl status phase3-deployment.service

# View detailed logs
sudo journalctl -u phase3-deployment.service -n 100

# Verify service file syntax
sudo systemctl daemon-reload
```

### Issue: Cannot switch to automation account

```bash
# Verify account exists and has shell
cat /etc/passwd | grep automation
# automation:x:1001:1001::/home/automation:/bin/bash

# Set proper shell
sudo chsh -s /bin/bash automation
```

---

## Summary: Proper Execution

### ✅ CORRECT (Service account, no sudo)

```bash
# Option 1: Wrapper (automatic)
bash scripts/redeploy/phase3-deployment-exec.sh

# Option 2: Direct switch
su - automation -c 'bash /path/to/phase3-deployment-trigger.sh'

# Option 3: Systemd (production)
sudo systemctl start phase3-deployment.service

# Option 4: SSH as automation
ssh automation@192.168.168.42 bash /path/to/phase3-deployment-trigger.sh
```

### ❌ INCORRECT (Violates constraints)

```bash
# DO NOT: Run as current user
bash /path/to/phase3-deployment-trigger.sh

# DO NOT: Use sudo (privilege escalation)
sudo bash /path/to/phase3-deployment-trigger.sh

# DO NOT: Run as root
su -
bash /path/to/phase3-deployment-trigger.sh

# DO NOT: Capture credentials in script
echo "password" | sudo -S bash ...
```

---

## Audit Trail Verification

All Phase 3 deployments executed as service account will show:

```json
{
  "timestamp": "2026-03-15T03:50:32Z",
  "deployment_id": "20260315-035032-2fac2327",
  "action": "deployment_initiated",
  "user": "automation",            ← Always automation
  "host": "192.168.168.42",
  "status": "success"
}
```

---

## Production Deployment Command (Recommended)

### Via Systemd (Zero-Touch Preferred)

```bash
# One-time setup
cd /home/akushnir/self-hosted-runner
sudo cp .systemd/phase3-deployment.service /etc/systemd/system/
sudo cp .systemd/phase3-deployment.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable phase3-deployment.timer

# Automatic daily execution starts
sudo systemctl start phase3-deployment.timer

# Monitor
sudo journalctl -u phase3-deployment.service -f
```

### Via SSH (One-Time Execution)

```bash
ssh automation@192.168.168.42 bash /home/akushnir/self-hosted-runner/scripts/redeploy/phase3-deployment-trigger.sh
```

### Via Wrapper (Interactive Testing)

```bash
bash scripts/redeploy/phase3-deployment-exec.sh
```

---

## Next Steps

1. ✅ **Verify service account exists:**
   ```bash
   id automation
   ```

2. ✅ **Test wrapper (dry-run):**
   ```bash
   bash scripts/redeploy/phase3-deployment-exec.sh
   ```

3. ✅ **Execute production deployment:**
   ```bash
   # Recommended: systemd timer (daily automation)
   sudo systemctl enable phase3-deployment.timer
   ```

4. ✅ **Monitor execution:**
   ```bash
   sudo journalctl -u phase3-deployment.service -f
   tail -f logs/phase3-deployment/audit-*.jsonl | jq .
   ```

---

**Constraint Enforced:** Service account only, no sudo escalation  
**Status:** ✅ Ready for production deployment  
**Next Action:** Execute as `automation` service account via method of choice  

---

**Document Version:** 1.0  
**Created:** March 15, 2026  
**Last Updated:** March 15, 2026
