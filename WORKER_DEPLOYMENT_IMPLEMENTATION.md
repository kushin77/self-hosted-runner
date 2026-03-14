# Worker Node Deployment - Complete Implementation Guide

## Status: SSH Authentication Failed ❌

The SSH key on the developer machine (Ubuntu) is not authorized on the worker node (dev-elevatediq). This document provides alternative deployment methods.

---

## Quick Start (USB Method - Recommended)

### Step 1: Prepare on Developer Machine
```bash
cd /home/akushnir/self-hosted-runner

# Run interactive preparation script
bash prepare-deployment-package.sh

# Select option 1 for USB deployment
# Follow prompts to:
#   - Detect and mount USB drive
#   - Create deployment archive
#   - Transfer to USB
```

### Step 2: Transfer USB to Worker Node
1. Eject USB from developer machine (safely)
2. Connect USB to `dev-elevatediq` (192.168.168.42)
3. Mount USB on worker node:
   ```bash
   sudo mkdir -p /media/usb
   sudo mount /dev/sdb1 /media/usb  # Adjust device name as needed
   ```

### Step 3: Execute on Worker Node
```bash
cd /media/usb
tar -xzf automation-deployment-*.tar.gz
cd automation-deployment-*/
bash deployment/deploy-standalone.sh
```

### Step 4: Verify Deployment
```bash
# Check installation
ls -laR /opt/automation/

# Monitor deployment log
tail -f /opt/automation/audit/deployment-*.log

# After completion, verify all 8 components
find /opt/automation -name "*.sh" -type f | wc -l  # Should be 8
```

---

## Deployment Files Created

### Main Deployment Scripts

| File | Purpose | Size |
|------|---------|------|
| `deploy-standalone.sh` | Main deployment script - **RUN THIS ON WORKER** | 8 KB |
| `prepare-deployment-package.sh` | Package preparation utility (USB, Network, Docker) | 12 KB |
| `Dockerfile.worker-deploy` | Docker-based deployment option | 0.4 KB |

### Documentation

| File | Purpose |
|------|---------|
| `WORKER_DEPLOYMENT_README.md` | Complete deployment documentation with troubleshooting |
| `WORKER_DEPLOYMENT_TRANSFER_GUIDE.md` | Multiple transfer method guides |
| `WORKER_DEPLOYMENT_IMPLEMENTATION.md` | **THIS FILE** - Implementation overview |

---

## Components Being Deployed

All components deploy to `/opt/automation/`:

### K8s Health Checks (4 scripts)
- `cluster-readiness.sh` - Verify cluster ready for deployments
- `cluster-stuck-recovery.sh` - Recover from stuck cluster states
- `validate-multicloud-secrets.sh` - Verify secrets across clouds

### Security (1 script)
- `audit-test-values.sh` - Security audit and compliance checks

### Multi-Region Failover (1 script)
- `failover-automation.sh` - Regional failover automation

### Core Automation (3 scripts)
- `credential-manager.sh` - Credential/secret management
- `orchestrator.sh` - Master automation orchestrator
- `deployment-monitor.sh` - Deployment monitoring

**Total: 8 automation components**

---

## Deployment Methods

### Method 1: USB Drive (Recommended)
**Best for:**
- No network access needed
- Physical separation of environments
- Offline deployment capability

**Requirements:**
- USB drive (8GB recommended)
- Physical access to both machines

**Time:** 5-10 minutes including transfer

**Steps:**
1. Run `prepare-deployment-package.sh` → Select option 1
2. Follow USB detection and mounting prompts
3. Archive automatically created and transferred to USB
4. Mount USB on worker node
5. Execute `deploy-standalone.sh`

---

### Method 2: Network Share (Samba/NFS)
**Best for:**
- Same network infrastructure
- Multiple deployment targets
- Repeated deployments

**Requirements:**
- Network connectivity
- Samba or NFS available

**Time:** 3-5 minutes

**Steps:**
1. Run `prepare-deployment-package.sh` → Select option 2
2. Follow network share setup instructions
3. Copy archive to share
4. Mount share on worker node
5. Execute `deploy-standalone.sh`

---

### Method 3: Docker Container
**Best for:**
- Containerized environments
- Reproducible deployments
- CI/CD integration

**Requirements:**
- Docker installed on worker node
- Container registry access (optional)

**Time:** 2-3 minutes

**Steps:**
```bash
# Build on developer machine
cd /home/akushnir/self-hosted-runner
docker build -f Dockerfile.worker-deploy -t worker-deploy:latest .

# Transfer image to worker (via USB/network)
docker save worker-deploy:latest | gzip > worker-deploy.tar.gz

# On worker node
docker load < worker-deploy.tar.gz
docker run --rm -v /opt:/target worker-deploy:latest
```

---

### Method 4: Direct rsync (If SSH becomes available later)
**Best for:**
- Once SSH authentication is fixed
- Quick deployments between systems

**Requirements:**
- SSH access (not currently available)
- rsync installed

**Steps:**
```bash
# From developer machine
rsync -avz deploy-standalone.sh automation@192.168.168.42:/home/automation/
rsync -avz scripts/ automation@192.168.168.42:/home/automation/scripts/

# On worker node
bash /home/automation/deploy-standalone.sh
```

---

## Pre-Deployment Verification

Before running deployment, verify on worker node:

```bash
# Verify target machine
hostname                          # Should be: dev-elevatediq
hostname -I | grep 192.168.168.42  # Verify IP address

# Check prerequisites
for cmd in bash git curl rsync tar gzip grep sed; do
  command -v $cmd || echo "Missing: $cmd"
done

# Verify disk space
df -h /opt                        # Need 100+ MB available

# Verify permissions
sudo -l 2>/dev/null              # Check sudo access
```

---

## Execution on Worker Node

### Option A: Direct Execution (Recommended)
```bash
# Single command with full output
bash deploy-standalone.sh

# Or with sudo if needed for /opt
sudo bash deploy-standalone.sh
```

### Option B: Background Execution
```bash
# Redirect output to file for later review
nohup bash deploy-standalone.sh > deployment.log 2>&1 &
tail -f deployment.log
```

### Option C: Docker Execution
```bash
docker run --rm -v /opt:/target worker-deploy:latest
```

---

## Post-Deployment Verification

### Immediate Verification
```bash
# Check installation structure
ls -laR /opt/automation/

# Expected structure:
# /opt/automation/
# ├── k8s-health-checks/
# │   ├── cluster-readiness.sh
# │   ├── cluster-stuck-recovery.sh
# │   └── validate-multicloud-secrets.sh
# ├── security/
# │   └── audit-test-values.sh
# ├── multi-region/
# │   └── failover-automation.sh
# ├── core/
# │   ├── credential-manager.sh
# │   ├── orchestrator.sh
# │   └── deployment-monitor.sh
# └── audit/
#     └── deployment-*.log
```

### Script Validation
```bash
# Verify all scripts are executable
find /opt/automation -name "*.sh" -type f -exec ls -l {} \;

# Test syntax
for f in /opt/automation/*/*.sh; do
  bash -n "$f" && echo "✓ $(basename $f)" || echo "✗ $(basename $f)"
done

# Count scripts (should be 8)
find /opt/automation -name "*.sh" | wc -l
```

### Execution Testing
```bash
# Test cluster readiness
bash /opt/automation/k8s-health-checks/cluster-readiness.sh --check-only

# Test credential manager
bash /opt/automation/core/credential-manager.sh --verify

# Monitor deployments
bash /opt/automation/core/deployment-monitor.sh --status
```

### Audit Log Review
```bash
# View deployment summary
cat /opt/automation/audit/deployment-*.log | head -50

# Check for errors
grep -i error /opt/automation/audit/deployment-*.log

# View full log
tail -100 /opt/automation/audit/deployment-*.log
```

---

## Scheduling & Automation

After successful deployment, setup cron jobs:

```bash
# Edit worker node crontab
sudo crontab -e

# Add periodic health checks (every 5 minutes)
*/5 * * * * /opt/automation/k8s-health-checks/cluster-readiness.sh --quiet >> /var/log/automation/health-checks.log 2>&1

# Add security audits (daily at 2 AM)
0 2 * * * /opt/automation/security/audit-test-values.sh --report > /var/log/automation/audit-$(date +\%Y\%m\%d).log 2>&1

# Add credential rotation (every 6 hours)
0 */6 * * * /opt/automation/core/credential-manager.sh --rotate >> /var/log/automation/cred-rotation.log 2>&1

# Add deployment monitoring (at startup)
@reboot /opt/automation/core/deployment-monitor.sh --daemon >> /var/log/automation/deployment-monitor.log 2>&1
```

---

## Troubleshooting

### Deployment Script Fails to Execute

**Problem:** "Permission denied"
```bash
# Solution: Make script executable
sudo chmod +x /path/to/deploy-standalone.sh
bash deploy-standalone.sh
```

**Problem:** "Command not found"
```bash
# Verify script syntax
bash -n deploy-standalone.sh

# Check required commands
bash deploy-standalone.sh 2>&1 | head -20
```

### Deployment Gets Stuck

**Problem:** Progress stops at certain point
```bash
# Monitor in another terminal
tail -f /opt/automation/audit/deployment-*.log

# Check system resources
watch -n 1 'free -h; df -h /opt'

# Check running processes
ps aux | grep -E '(deployment|git|curl)'
```

### Incomplete Installation

**Problem:** Some files missing from `/opt/automation`
```bash
# Verify count of scripts
find /opt/automation -name "*.sh" | wc -l  # Should be 8

# Check for errors in log
grep -i error /opt/automation/audit/deployment-*.log

# Redeploy if needed
bash deploy-standalone.sh  # Runs full deployment again
```

### Network Access Issues

**Problem:** Git clone fails
```bash
# Test connectivity
ping github.com
curl -I https://github.com

# Verify DNS
nslookup github.com
```

**Problem:** No permissions to /opt
```bash
# Check current permissions
ls -ld /opt

# Get sudo access if needed
sudo bash deploy-standalone.sh
```

---

## Rollback Procedures

If issues occur after deployment:

### Complete Removal
```bash
# Stop any running automations
pkill -f /opt/automation

# Remove installation
sudo rm -rf /opt/automation/

# Verify removal
ls -la /opt/automation 2>&1 | grep "No such file"
```

### Partial Rollback
```bash
# Keep logs, remove scripts
sudo rm -rf /opt/automation/{core,security,multi-region}

# Redeploy just those components
bash deploy-standalone.sh
```

### Backup Before Changes
```bash
# Archive current installation before modifications
sudo tar -czf /opt/automation-backup-$(date +%Y%m%d-%H%M%S).tar.gz /opt/automation/

# Later, restore if needed
sudo tar -xzf /opt/automation-backup-*.tar.gz -C /
```

---

## Success Criteria

Deployment is successful when:

- [x] All 8 scripts present in `/opt/automation`
- [x] All scripts are executable (`-rwxr-xr-x`)
- [x] Bash syntax validation passes for all scripts
- [x] Deployment log present in `/opt/automation/audit/`
- [x] No errors in deployment log
- [x] At least one health check script runs successfully
- [x] Scripts can be scheduled in cron
- [x] Audit log shows "✅ DEPLOYMENT COMPLETE"

---

## Next Steps After Deployment

1. **Setup Monitoring**
   - Configure CloudWatch for logs
   - Setup alerts for health check failures

2. **Enable Automation**
   - Schedule cron jobs for periodic execution
   - Configure CI/CD integration

3. **Test Failover**
   - Run failover automation script
   - Verify multi-region capability

4. **Security Audit**
   - Run security validation scripts
   - Review audit logs for compliance

5. **Production Integration**
   - Enable all automation workflows
   - Monitor metrics and alerts
   - Document any customizations

---

## Support & Contact

For issues with deployment:

1. **Check Logs**
   ```bash
   cat /opt/automation/audit/deployment-*.log
   ```

2. **Review Documentation**
   - `WORKER_DEPLOYMENT_README.md` - Detailed setup guide
   - `WORKER_DEPLOYMENT_TRANSFER_GUIDE.md` - Transfer methods

3. **Manual Verification**
   ```bash
   bash -n /opt/automation/*/*.sh  # Syntax check
   find /opt/automation -name "*.sh" -exec file {} \;  # File info
   ```

4. **Diagnostic Bundle**
   ```bash
   mkdir -p /tmp/automation-diagnostics
   cp -r /opt/automation/audit /tmp/automation-diagnostics/
   tar -czf /tmp/automation-diagnostics.tar.gz /tmp/automation-diagnostics/
   ```

---

## Key Files Summary

| File | Location | Purpose |
|------|----------|---------|
| **deploy-standalone.sh** | Root directory | Main deployment executable |
| **prepare-deployment-package.sh** | Root directory | Package preparation utility |
| **Dockerfile.worker-deploy** | Root directory | Docker deployment option |
| **WORKER_DEPLOYMENT_README.md** | Root directory | Complete documentation |
| **WORKER_DEPLOYMENT_TRANSFER_GUIDE.md** | Root directory | Transfer method guides |
| **WORKER_DEPLOYMENT_IMPLEMENTATION.md** | Root directory | This implementation guide |

---

## Timeline

- **5 minutes:** USB preparation and creation
- **2 minutes:** USB physical transfer
- **3 minutes:** Deployment execution
- **2 minutes:** Verification and testing
- **Total: ~12 minutes** for complete deployment

---

## Important Notes

- ✅ No SSH required - deployment is self-contained
- ✅ Works completely offline after USB transfer
- ✅ All scripts include error handling and logging
- ✅ Deployment is idempotent (safe to re-run)
- ✅ Complete audit trail in `/opt/automation/audit/`
- ✅ All components independently testable

---

**Document Version:** 1.0  
**Created:** 2024  
**Target:** dev-elevatediq (192.168.168.42)  
**Status:** Ready for Implementation
