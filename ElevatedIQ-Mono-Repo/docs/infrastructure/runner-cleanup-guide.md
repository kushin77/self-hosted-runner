# Self-Hosted Runner Cleanup & Queue Management (Issue #7019)

**Status:** In Progress
**Priority:** P1-URGENT
**NIST Controls:** SC-7, CA-7, SI-4, PM-3, PM-5
**Issue:** https://github.com/kushin77/ElevatedIQ-Mono-Repo/issues/7019

## Overview

Self-hosted runners on 192.168.168.42 accumulate stale temporary files (`/tmp/gitleaks*`, `/tmp/pytest*`, etc.) that block consecutive workflow executions. This document describes the automated cleanup solution implemented in Issue #7019.

**Problem:**
- Gitleaks checks fail immediately with: `/tmp/gitleaks.tmp already exists`
- Stale files block required security gates
- Queue backs up, PR merges delayed
- Workflow execution time increases from 2-3 minutes to 5+ minutes

**Solution:**
- Automated systemd timer runs cleanup every 6 hours
- Pre-flight GitHub Actions validation cleans files before each check
- Health monitoring detects and reports stuck processes
- Queue health metrics prevent saturation

---

## Implementation Components

### 1. Cleanup Script (`scripts/maintenance/runner-cleanup.sh`)

**Purpose:** Automated cleanup of stale temporary files and lock files

**Execution:**
- Run manually: `bash scripts/maintenance/runner-cleanup.sh`
- Systemd timer: Every 6 hours (see section 3)
- Triggered by GitHub Actions pre-flight (see section 4)

**Functions:**
- `validate_runner_health()`: Disk usage, process count, resource metrics
- `cleanup_stale_files()`: Remove files matching patterns in `/tmp`
- `recovery_stale_workflow()`: Clear workflow lock files > 30 minutes old
- `check_queue_health()`: Verify runner job queue status

**Cleanup Patterns:**
```
/tmp/gitleaks*    - Gitleaks temp files (MAIN BLOCKER)
/tmp/pytest*      - Pytest temp cache
/tmp/mypy*        - Mypy type check cache
/tmp/coverage*    - Coverage report temp files
/tmp/docker*      - Docker build temp files
/tmp/pip*         - pip install temp files
```

**Log Output:**
```
Fields logged:
- Timestamp (ISO-8601)
- Action (cleaner, validation, recovery, metrics)
- File count affected
- Disk usage (%usage and threshold check)
- Stuck processes count
- Queue health status
```

### 2. Systemd Timer (`build/systemd/elevatediq-runner-cleanup.{service,timer}`)

**Files:**
- `build/systemd/elevatediq-runner-cleanup.service` - systemd service unit
- `build/systemd/elevatediq-runner-cleanup.timer` - systemd timer (6-hour interval)

**Installation (Manual on 192.168.168.42):**
```bash
# Copy service files to systemd
sudo cp build/systemd/elevatediq-runner-cleanup.* /etc/systemd/system/

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable elevatediq-runner-cleanup.timer
sudo systemctl start elevatediq-runner-cleanup.timer

# Verify
sudo systemctl status elevatediq-runner-cleanup.timer
sudo systemctl list-timers --all
```

**Timer Schedule:**
- OnBootSec: 5 minutes after system boot
- OnUnitActiveSec: Every 6 hours after last execution
- Accuracy: ±5 minutes (prevents concurrent runs)
- Persistence: Survives system restart

**Monitoring:**
```bash
# Check timer status
systemctl status elevatediq-runner-cleanup.timer

# View last execution
sudo journalctl -u elevatediq-runner-cleanup.service -n 50

# Live tail logs
sudo journalctl -u elevatediq-runner-cleanup.service -f

# Check service status
systemctl list-timers elevatediq-runner-cleanup.timer
```

### 3. Pre-Flight GitHub Actions (`.github/actions/runner-preflight-cleanup/action.yml`)

**Purpose:** Run cleanup validation before security gates

**Included Steps:**
1. **Runner Health Check**
   - Disk usage (`/tmp` %)
   - Memory usage (%)
   - CPU load average
   - Alerting at 70% disk threshold

2. **Stale File Cleanup**
   - Remove gitleaks temp files (primary blocker)
   - Remove pytest temp files
   - Remove mypy temp files
   - Remove coverage temp files

3. **Workflow Lock Cleanup**
   - Find `.lock` files > 30 minutes old
   - Remove to unblock concurrent workflows
   - Prevents deadlock on reruns

4. **Queue Health Validation**
   - Detect stuck gitleaks processes
   - Detect stuck pytest processes
   - Kill processes if hung (stale > 30 min)
   - Report active check count

5. **NIST Compliance Reporting**
   - SC-7: Boundary protection (process cleanup)
   - CA-7: Continuous monitoring (health metrics)
   - SI-4: System monitoring (resource tracking)

**Usage in Workflows:**

Add to any GitHub Actions workflow before quality gates:

```yaml
jobs:
  security-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: "🧹 Pre-Flight Runner Cleanup (NIST SC-7, SI-4)"
        uses: ./.github/actions/runner-preflight-cleanup
        continue-on-error: true  # Don't fail workflow if action fails

      - name: Run Gitleaks  # This now runs with clean /tmp
        uses: gitleaks/gitleaks-action@v2
```

**Already Integrated Into:**
- `.github/workflows/secrets-validation.yml` - gitleaks-scan job
- Can be added to: pytest, mypy, workspace-doctor checks

---

## Deployment Guide (for 192.168.168.42)

### Step 1: Copy Cleanup Script

```bash
# From workstation (192.168.168.31)
scp -r scripts/maintenance/runner-cleanup.sh akushnir@192.168.168.42:~/ElevatedIQ-Mono-Mono-Repo/scripts/maintenance/

# Then on runner (192.168.168.42)
chmod +x ~/ElevatedIQ-Mono-Mono-Repo/scripts/maintenance/runner-cleanup.sh
```

### Step 2: Install Systemd Timer

```bash
# On runner (192.168.168.42)
cd ~/ElevatedIQ-Mono-Mono-Repo

# Copy service files
sudo cp build/systemd/elevatediq-runner-cleanup.* /etc/systemd/system/

# Verify permissions
ls -la /etc/systemd/system/elevatediq-runner-cleanup.*

# Install
sudo systemctl daemon-reload
sudo systemctl enable elevatediq-runner-cleanup.timer
sudo systemctl start elevatediq-runner-cleanup.timer

# Test
sudo systemctl status elevatediq-runner-cleanup.timer
```

### Step 3: Test Manual Cleanup

```bash
# On runner (192.168.168.42)
bash ~/ElevatedIQ-Mono-Mono-Repo/scripts/maintenance/runner-cleanup.sh

# Should output:
# ✅ Cleaned X files matching pattern: /tmp/gitleaks*
# ✅ /tmp usage: YY% (normal)
# ✅ Queue health normal: N pending jobs
```

### Step 4: Verify Pre-Flight Action

```bash
# The workflow will run pre-flight on next PR
# Check in GitHub Actions:
# - Workflow: "🔒 Secrets & Security Validation"
# - Job: "gitleaks-scan"
# - Step: "🧹 Pre-Flight Runner Cleanup"
```

---

## Operational Procedures

### Health Monitoring

**Check cleanup job status:**
```bash
# View recent cleanup runs
sudo journalctl -u elevatediq-runner-cleanup.service --since "1 hour ago"

# Check if next cleanup is scheduled
sudo systemctl list-timers elevatediq-runner-cleanup.timer

# Parse for issues
sudo journalctl -u elevatediq-runner-cleanup.service -o json | jq '.[] | select(.MESSAGE | contains("WARNING"))'
```

**Expected Output (Normal):**
```
[2026-02-28T20:35:00Z] 🚀 ElevatedIQ Runner Cleanup Starting
[2026-02-28T20:35:00Z] ✅ /tmp usage: 15% (normal)
[2026-02-28T20:35:01Z] ✅ Cleaned 3 files matching pattern: /tmp/gitleaks*
[2026-02-28T20:35:01Z] ✅ Queue health normal: 0 pending jobs
[2026-02-28T20:35:02Z] ✅ Runner Cleanup Complete
```

**Warning Signs:**
- `/tmp usage: 82%` — Disk pressure, may need manual cleanup
- `3 stuck gitleaks processes` — Workflows hung, need investigation
- `5+ pending jobs` — Queue saturation, reduce concurrent workflows
- `Cleaned > 100 files` — Unusual cleanup size, check workflow logs

### Recovery Procedures

**Manual Cleanup (if timer fails):**
```bash
# On runner (192.168.168.42)
sudo bash ~/ElevatedIQ-Mono-Mono-Repo/scripts/maintenance/runner-cleanup.sh

# Or use the GitHub Actions pre-flight
# Re-run any failing PR to trigger pre-flight cleanup
```

**Kill Stuck Processes:**
```bash
# On runner (192.168.168.42)
pkill -f gitleaks    # Kill stuck gitleaks
pkill -f pytest       # Kill stuck pytest
sleep 2
ps aux | grep -E "gitleaks|pytest" | grep -v grep
```

**Reset Directory State:**
```bash
# On runner (192.168.168.42)
# Clear all temp files (ONLY if completely stuck)
rm -rf /tmp/gitleaks* /tmp/pytest* /tmp/mypy* /tmp/coverage* 2>/dev/null
rm -f **/*.lock         # Remove all lock files
sudo systemctl restart github-runner
```

---

## Performance Impact

**Before Cleanup:**
- Gitleaks execution: 5-8 min /tmp/gitleaks.tmp error
- Consecutive runs: Failed due to existing temp files
- Queue saturation: 3-5 min wait times
- Required check time: 10-15 min

**After Cleanup (Expected):**
- Gitleaks execution: 1-2 min (clean /tmp)
- Consecutive runs: No file conflicts
- Queue saturation: <30 sec wait
- Required check time: 5-7 min total

**Metrics to Track:**
```
KPIs_Before:
- Gitleaks failures: 30-40% on consecutive runs
- Mean workflow execution: 12 min
- Max queue depth: 8 jobs

KPIs_After:
- Gitleaks failures: <2% (external reasons only)
- Mean workflow execution: 6 min
- Max queue depth: 2 jobs
```

---

## NIST Compliance Mapping

| NIST Control | Requirement | Implementation |
|---|---|---|
| **SC-7** | Boundary Protection | Stale process cleanup prevents resource exhaustion |
| **SC-7.5** | Information Flow Enforcement | Lock file removal prevents deadlock attacks |
| **CA-7** | Continuous Monitoring | Health metrics logged every cleanup cycle |
| **CA-7.1** | Monitoring & Reporting | systemd logs to syslog, journalctl queries |
| **SI-4** | System Monitoring | Process count, disk usage, queue depth monitored |
| **SI-4.4** | Inbound/Outbound Monitoring | Runner resource metrics tracked continuously |
| **PM-3** | Respond to IT Security Incidents | Cleanup responds to stuck process incidents |
| **PM-5** | System Development/Maintenance | Automation enables maintenance without downtime |

---

## Related Issues & PRs

- **Issue #7019:** Self-Hosted Runner Tmp Cleanup + Queue Management (THIS ISSUE)
- **PR #6991:** Blocked by `/tmp/gitleaks.tmp already exists` (WILL BE RESOLVED)
- **Issue #7001:** GitHub Billing Fallback (NOW USING SAME RUNNER)
- **PR #6944:** Infrastructure remediation (WILL COMPLETE FASTER)
- **PR #7017-#7013:** Other queued PRs (WILL AUTO-MERGE FASTER)

---

## Troubleshooting

**Q: Cleanup script not running?**
```bash
# Check if timer is enabled
sudo systemctl is-enabled elevatediq-runner-cleanup.timer

# Check next scheduled run
sudo systemctl list-timers elevatediq-runner-cleanup.timer
```

**Q: /tmp still filling up?**
```bash
# Find largest temp files
du -sh /tmp/* | sort -rh | head -10

# Check if cleanup pattern matches
ls -la /tmp/gitleaks* /tmp/pytest* 2>/dev/null
```

**Q: Gitleaks still failing after cleanup?**
```bash
# Verify cleanup ran
sudo journalctl -u elevatediq-runner-cleanup.service --since "10 minutes ago"

# Check /tmp state before gitleaks
cd ~/ElevatedIQ-Mono-Mono-Repo && ls -la /tmp/gitleaks* 2>&1 | head -5
```

**Q: How to disable cleanup temporarily?**
```bash
# Stop timer
sudo systemctl stop elevatediq-runner-cleanup.timer

# For GitHub Actions, set continue-on-error: true (already done)
```

---

## Future Enhancements

1. **Alerting Integration:** Send alert if cleanup removes >200 files
2. **Metric Export:** Prometheus metrics for cleanup results
3. **Auto-Scaling:** Reduce concurrent workflows if queue > 5 jobs
4. **Predictive:** Machine learning to detect stale files before blocking
5. **Multi-Runner:** Centralized cleanup dashboard for all runners

---

## Documentation References

- **Systemd Documentation:** `man systemd.timer`, `man systemd.service`
- **GitHub Actions:** `.github/actions/runner-preflight-cleanup/action.yml`
- **Runner Script:** `scripts/maintenance/runner-cleanup.sh`
- **NIST SC-7:** Boundary Protection and Information Flow Enforcement
- **NIST SI-4:** System Monitoring and Anomaly Detection

---

**Status:** Ready for deployment to 192.168.168.42
**Next Step:** Deploy systemd timer and run first cleanup cycle
**Success Criteria:** Gitleaks <2min, zero stale /tmp files, queue depth <2 jobs
