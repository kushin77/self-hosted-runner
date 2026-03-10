# Phase 2: Automated Operations Deployment Guide

**Status**: Ready for execution (requires sudo access)

## Commands to Run (with sudo)

```bash
# 1. Install systemd service/timer files
sudo cp /home/akushnir/self-hosted-runner/scripts/systemd/*.service /etc/systemd/system/
sudo cp /home/akushnir/self-hosted-runner/scripts/systemd/*.timer /etc/systemd/system/

# 2. Create logging directory
sudo mkdir -p /var/log/nexusshield
sudo chmod 755 /var/log/nexusshield

# 3. Reload systemd daemon to recognize new units
sudo systemctl daemon-reload

# 4. Enable timers to start on system boot
sudo systemctl enable nexusshield-credential-rotation.timer
sudo systemctl enable nexusshield-terraform-backup.timer
sudo systemctl enable nexusshield-compliance-audit.timer

# 5. Start timers immediately
sudo systemctl start nexusshield-credential-rotation.timer
sudo systemctl start nexusshield-terraform-backup.timer
sudo systemctl start nexusshield-compliance-audit.timer

# 6. Verify installation
sudo systemctl list-timers nexusshield-*
sudo journalctl -u nexusshield-credential-rotation.timer -n 10

# 7. Check next execution times
sudo systemctl status nexusshield-credential-rotation.timer
sudo systemctl status nexusshield-terraform-backup.timer
sudo systemctl status nexusshield-compliance-audit.timer
```

## What Gets Installed

### 1. Credential Rotation Timer
- **File**: `nexusshield-credential-rotation.service` + `.timer`
- **Schedule**: Daily at 03:00 UTC
- **Purpose**: Rotate GSM/Vault/KMS credentials every 30 days (15-min SLA for emergencies)
- **Logs**: `/var/log/nexusshield/credential-rotation.log`
- **Audit Trail**: `logs/credential-rotations/{YYYY-MM-DD}.jsonl` (immutable JSONL)
- **Issues Closed**: #2257, #2200

### 2. Terraform State Backup Timer
- **File**: `nexusshield-terraform-backup.service` + `.timer`
- **Schedule**: Every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
- **Purpose**: Backup Terraform state to GCS with versioning
- **Retention**: 90 days hot storage, 365 days archive
- **Integrity**: SHA256 hash verification
- **Logs**: `/var/log/nexusshield/terraform-backup.log`
- **Audit Trail**: `logs/deployments/{YYYY-MM-DD}.jsonl` (immutable JSONL)
- **Issues Closed**: #2260

### 3. Compliance Audit Timer
- **File**: `nexusshield-compliance-audit.service` + `.timer`
- **Schedule**: Monthly on 1st of month at 02:00 UTC
- **Purpose**: Verify immutable audit trails, credential rotation, and NO GitHub Actions policy
- **Checklist**: 4-week compliance verification (file integrity, completeness, retention)
- **Logs**: `/var/log/nexusshield/compliance-audit.log`
- **Audit Trail**: `logs/deployments/{YYYY-MM-DD}-compliance.jsonl`
- **Issues Closed**: #2276, #2275, #2274

## Prerequisite Checks

Before running sudo commands, verify:

```bash
# Check files exist
ls -la scripts/systemd/

# Check scripts are executable
ls -la scripts/post-deployment/*.sh
ls -la scripts/compliance/*.sh

# Check paths in files
grep -r "ExecStart=" scripts/systemd/

# Verify no hardcoded passwords or secrets
grep -r "password\|secret\|key\|token" scripts/systemd/
```

## Rollback Instructions

If needed to remove:

```bash
sudo systemctl stop nexusshield-credential-rotation.timer
sudo systemctl stop nexusshield-terraform-backup.timer
sudo systemctl stop nexusshield-compliance-audit.timer

sudo systemctl disable nexusshield-credential-rotation.timer
sudo systemctl disable nexusshield-terraform-backup.timer
sudo systemctl disable nexusshield-compliance-audit.timer

sudo rm /etc/systemd/system/nexusshield-*.service
sudo rm /etc/systemd/system/nexusshield-*.timer

sudo systemctl daemon-reload
```

## Automation Scripts (Already Created)

These are called by the systemd timers:

1. **credential-rotation.sh** (300 lines)
   - 4-layer cascade: GSM → Vault → KMS → Local Cache
   - 30-day rotation cycle (15-minute emergency mode)
   - Immutable audit logging

2. **terraform-state-backup.sh** (180 lines)
   - Automated GCS backup with versioning
   - 6-hour schedule via Cloud Scheduler
   - Lifecycle policies and integrity checks

3. **provision-secrets.sh** (380 lines)
   - Bootstrap secrets on startup
   - 4-layer fallback resolution
   - Offline cache validation

4. **monitoring-setup.sh** (400 lines)
   - Cloud Monitoring dashboards
   - Alert policies (error rate, latency, connection pool)
   - Logging and retention configuration

5. **postgres-exporter-setup.sh** (380 lines)
   - Prometheus metrics integration
   - 11+ Postgres metric types
   - Health check configuration

6. **monthly-audit-trail-check.sh** (250 lines)
   - Weekly compliance verification
   - File integrity, completeness, retention validation
   - SHA256 hash verification

## Timeline

- **Phase 1**: Infrastructure (Terraform) - 10 minutes
- **Phase 2**: Systemd Installation - 2 minutes (requires sudo)
- **Phase 3**: Credentials Provisioning - 5 minutes
- **Phase 4**: Post-Deployment Setup - 15 minutes (parallel)
- **Phase 5**: Monitoring & Validation - 5 minutes
- **Phase 6**: Issue Closeout - 3 minutes

**Total**: ~30 minutes end-to-end

## Related GitHub Issues

- #2191 - Portal MVP Phase 1 Deployment
- #2216 - Production Deployment Ready
- #2202 - Disable GitHub Actions
- #2201 - Configure Production Environment
- #2200 - Install Credential Rotation Timer ← **THIS PHASE**
- #2260 - Automate Terraform State Backup ← **THIS PHASE**
- #2257 - Schedule Credential Rotation ← **THIS PHASE**
- #2256 - Post-Deployment Monitoring Setup
- #2241 - Integrate Secret Provisioning
- #2240 - Integrate postgres_exporter
- #2276 - Monthly Audit Trail Compliance ← **THIS PHASE**
- #2275 - Monthly Credential Rotation Validation
- #2274 - Continuous NO GitHub Actions Enforcement

## Next Steps

1. Run the sudo commands above to install systemd files
2. Verify timers are active: `sudo systemctl list-timers nexusshield-*`
3. Proceed to Phase 3: Credentials Provisioning
4. Execute Phase 4: Post-Deployment Automation
5. Complete Phase 5: Monitoring & Validation
6. Phase 6: Close all GitHub issues with completion evidence

---

**Created**: 2026-03-10 12:49 UTC
**Status**: ✅ Ready for sudo execution
**Audit Trail**: All actions logged to immutable JSONL files
