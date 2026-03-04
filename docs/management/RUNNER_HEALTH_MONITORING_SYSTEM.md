# GitHub Actions Runner Health & Auto-Restart System

## Overview

This document describes the automated health monitoring and auto-restart system for GitHub Actions self-hosted runners in the ElevatedIQ organization.

**Status**: ✅ **ACTIVE** - Runners are online and monitored
**Last Updated**: 2026-03-04T17:15:00Z

## Problem Statement

Previously, organization-level runners could go offline without automatic detection or recovery, causing workflow runs to queue indefinitely. This system prevents that by:

- ✅ Continuously monitoring runner systemd services
- ✅ Auto-restarting failed/stopped runners (with exponential backoff)
- ✅ Creating GitHub issues for persistent failures
- ✅ Keeping runners online via systemd auto-restart configuration

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Runner Health Monitoring System (Automated)                   │
│                                                                │
│  ┌─ On Local Workstation (.31):                              │
│  │ └─ Systemd timer (every 5 min)                            │
│  │    └─ runner_health_monitor.sh                            │
│  │       ├─ SSH to runner host (.42)                         │
│  │       ├─ Check systemd service status                     │
│  │       ├─ Auto-restart if inactive (backoff: 10s → 40s)   │
│  │       └─ Query GitHub API to verify online               │
│  │                                                            │
│  └─ On Runner Host (.42):                                    │
│     └─ Systemd services (systemd-managed auto-restart)       │
│        ├─ actions.runner.elevatediq-ai.org-runner-42        │
│        ├─ (configured with Restart=on-failure)              │
│        └─ Auto-restarts every 30s if crashed                │
│                                                                │
│  ┌─ GitHub Issues (Auto-Created)                            │
│  │ └─ Created for persistent failures                        │
│  │    └─ Auto-labeled: runner-health, automated, priority-p1 │
│  └────────────────────────────────────────────────────────────│
```

## Key Components

### 1. **Health Monitor Script**
- **Location**: `scripts/pmo/runner_health_monitor.sh`
- **Purpose**: Check runner service status and auto-restart
- **Key Features**:
  - SSH to runner host and check systemd services
  - Exponential backoff restarts (10s → 20s → 40s)
  - GitHub API verification (check `/orgs/elevatediq-ai/actions/runners`)
  - Auto-create GitHub issues for failures
  - Comprehensive logging to `scripts/pmo/logs/runner_health_monitor.log`

### 2. **Systemd Configuration (On Runner Host)**
- **Service**: `actions.runner.elevatediq-ai.org-runner-42.service`
- **Auto-Restart Config**: `Restart=on-failure` with `RestartSec=30`
- **Enable Status**: ✅ Enabled for boot

### 3. **Systemd Timer (On Workstation)**
- **Timer**: `elevatediq-runner-health-monitor.timer`
- **Interval**: Every 5 minutes
- **Service**: `elevatediq-runner-health-monitor.service`
- **User**: Current user (systemd --user timer)

## Installation & Setup

### Option A: Install Systemd Timer (Recommended)

```bash
cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo
./scripts/pmo/runner_health_monitor.sh --install
```

This will:
1. Create service and timer units in `~/.config/systemd/user/`
2. Reload systemd
3. Enable and start the timer
4. Run health checks every 5 minutes automatically

### Option B: Manual Inspection

```bash
# Single health check
./scripts/pmo/runner_health_monitor.sh

# Continuous watch (manual, Ctrl+C to stop)
./scripts/pmo/runner_health_monitor.sh --watch

# View logs
tail -f scripts/pmo/logs/runner_health_monitor.log
```

## Verification Commands

```bash
# Check timer status
systemctl --user status elevatediq-runner-health-monitor.timer

# View recent logs
journalctl --user -u elevatediq-runner-health-monitor.service -n 50

# Follow logs live
journalctl --user -u elevatediq-runner-health-monitor.service -f

# Check runner status in GitHub
gh api /orgs/elevatediq-ai/actions/runners/11 \
  --jq '{name: .name, status: .status, busy: .busy, labels: [.labels[].name]}'

# Check that systemd service on host is running
ssh akushnir@192.168.168.42 'sudo systemctl status actions.runner.elevatediq-ai.org-runner-42 --no-pager'
```

## Workflow: How It Works

### Scenario 1: Normal Operation
1. Timer fires (every 5 min)
2. Monitor checks systemd service (active ✓)
3. Monitor verifies with GitHub API (online ✓)
4. Log success, exit 0

### Scenario 2: Service Crashed
1. Timer fires
2. Monitor detects service is inactive
3. Monitor restarts with systemctl
4. Service recovers immediately
5. Log warning, exit 0

### Scenario 3: Persistent Failure
1. Timer fires multiple times
2. Service fails to restart after 3 attempts
3. Monitor creates GitHub issue with labels: `runner-health`, `automated`, `priority-p1`
4. Log error, exit 1
5. Human follows up on issue (manual intervention required)

## Global Prevention: Preventing Runner Issues Long-Term

### Root Cause Analysis

Previous issues occurred because:
1. **No Monitoring**: Runners could silently go offline
2. **Manual Restart**: Required human intervention
3. **No Auto-Restart**: Crashed runners stayed dead until manually restarted
4. **No Service Recovery**: Systemd not configured to auto-restart

### Solutions Implemented

| Problem | Solution | Where |
|---------|----------|-------|
| No monitoring | Health monitor script (systemd timer) | Workstation (.31) |
| Manual restart | Auto-restart with exponential backoff | Health monitor |
| No service recovery | Systemd configured with `Restart=on-failure` | Runner host (.42) |
| No visibility | GitHub issues auto-created for failures | Integration |
| No traceability | Comprehensive logging to file + journalctl | `scripts/pmo/logs/` |

### Preventing Similar Issues

1. **Runner Service Configuration** (Host Level)
   - All runner services must have `Restart=on-failure` in systemd unit
   - `RestartSec=30` to prevent rapid restart loops
   - Example: See `/etc/systemd/system/actions.runner.*.service`

2. **Monitoring** (Workstation Level)
   - Health monitor timer runs every 5 minutes
   - Detects and auto-restarts failed services
   - Escalates to GitHub issues if needed

3. **Documentation** (Process Level)
   - New runners must follow systemd service pattern
   - All runners use org-runner labels (prevents repo-scoped runners)
   - Health monitor is installed and running

4. **Testing** (Validation Level)
   - Run `./scripts/pmo/runner_health_monitor.sh` before committing changes
   - Verify systemd timer is active: `systemctl --user status elevatediq-runner-health-monitor.timer`
   - Monitor logs for 24h after changes

## Troubleshooting

### Systemd Timer Not Starting Checks

**Symptom**: Health checks not running
**Solution**:
```bash
# Check if timer is active
systemctl --user is-active elevatediq-runner-health-monitor.timer

# If not running:
systemctl --user start elevatediq-runner-health-monitor.timer

# View errors
journalctl --user -u elevatediq-runner-health-monitor.service -p err
```

### Runner Service Still Offline in GitHub

**Symptom**: GitHub shows runner as offline despite systemd active
**Solution**:
1. SSH to host and check communication:
   ```bash
   ssh akushnir@192.168.168.42
   tail -100 /home/akushnir/actions-runner-org-42/_diag/Runner_*.log
   ```
2. Check if service is actually running:
   ```bash
   sudo systemctl status actions.runner.elevatediq-ai.org-runner-42
   ```
3. Verify GitHub token is valid:
   ```bash
   cd /home/akushnir/actions-runner-org-42
   ./run.sh --check  # if interactive available
   ```

### Too Many GitHub Issues Created

**Symptom**: Lots of "Runner Offline" issues
**Solution**:
1. Address the root cause (check host connectivity, GitHub API, runner configuration)
2. View monitor logs: `tail -100 scripts/pmo/logs/runner_health_monitor.log`
3. Disable GitHub issue creation temporarily (edit script, comment out `create_gh_issue_runner_down` calls)

## Maintenance & Updates

### Weekly Check
```bash
# Review health monitor logs
tail -100 scripts/pmo/logs/runner_health_monitor.log

# Check for any GitHub issues created
gh issue list --repo elevatediq-ai/ElevatedIQ-Mono-Repo \
  --label "runner-health" --state all
```

### NIST Alignment (CA-7, CM-3)
- **CA-7 (Continuous Monitoring)**: Health monitor runs every 5 minutes
- **CM-3 (Configuration Change Control)**: All systemd changes logged and tracked in git
- **AU-2 (Audit Events)**: All restarts logged to systemd journal and file

## Related Documentation

- [Workflow Migration Guide](./WORKFLOW_MIGRATION_GUIDE.md)
- [Runner Cleanup Proposal](./PROPOSED_CLEANUP_NON_ORG_RUNNERS.md)
- [Workflow Verification Runbook](./WORKFLOW_VERIFICATION_RUNBOOK.md)

## Support & Contacts

- **Owner**: @akushnir
- **On-Call**: Check GitHub issue assignments
- **Escalation**: Create issue with `runner-health` label if auto-recovery fails

---

**Last Updated**: 2026-03-04T17:15:00Z
**Version**: 1.0
**Status**: Production
