# Runner Health Monitor Operations Runbook

**Deployment Date:** 2026-03-04
**Target Node:** 192.168.168.42 (dev-elevatediq)
**Status:** ✅ LIVE
**Run Interval:** Every 5 minutes

---

## 🚀 Quick Start

### Check Status
```bash
# Connect to production node
ssh akushnir@192.168.168.42

# View timer status
sudo systemctl status elevatediq-runner-health-monitor.timer

# View next scheduled run
sudo systemctl list-timers elevatediq-runner-health-monitor.timer
```

### View Live Logs
```bash
# Real-time service logs
sudo journalctl -u elevatediq-runner-health-monitor.service -f

# Last 50 lines
sudo journalctl -u elevatediq-runner-health-monitor.service -n 50

# Logs from last 1 hour
sudo journalctl -u elevatediq-runner-health-monitor.service --since "1 hour ago"
```

### View Metrics
```bash
# List all metrics files
ls -lh /var/cache/elevatediq/metrics/*.prom

# View specific metric
cat /var/cache/elevatediq/metrics/checks_total.prom
cat /var/cache/elevatediq/metrics/restarts_total.prom
cat /var/cache/elevatediq/metrics/failures_total.prom
```

---

## 📋 Common Operations

### Manually Trigger Health Check
```bash
# Run once immediately
sudo systemctl start elevatediq-runner-health-monitor.service

# Wait for completion
sleep 5

# View output
sudo journalctl -u elevatediq-runner-health-monitor.service -n 30 --no-pager
```

### Stop Timer (Maintenance Mode)
```bash
# Stop timer (prevents automatic runs)
sudo systemctl stop elevatediq-runner-health-monitor.timer

# Verify stopped
sudo systemctl status elevatediq-runner-health-monitor.timer
```

### Resume after Maintenance
```bash
# Start timer again
sudo systemctl start elevatediq-runner-health-monitor.timer

# Verify running
sudo systemctl status elevatediq-runner-health-monitor.timer
```

### View Service Configuration
```bash
# Service unit
sudo cat /etc/systemd/system/elevatediq-runner-health-monitor.service

# Timer unit
sudo cat /etc/systemd/system/elevatediq-runner-health-monitor.timer

# Script location
ls -lh /opt/elevatediq/bin/runner_health_monitor.sh
```

---

## 🔍 Troubleshooting

### Service Failed to Start
```bash
# Check latest error
sudo journalctl -u elevatediq-runner-health-monitor.service -n 20 --no-pager

# Check service status
sudo systemctl status elevatediq-runner-health-monitor.service

# Validate script syntax
bash -n /opt/elevatediq/bin/runner_health_monitor.sh
```

### No Runners Found (Expected Behavior)
If logs show `[ERROR] No runner systemd services found on host`, this is **normal** on fresh nodes without GitHub Actions runners installed. The monitor will:
- Log the condition
- Continue monitoring
- Retry on next interval

To install a GitHub Actions runner:
```bash
# See: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners
# Runners should register as systemd services
```

### Metrics Not Being Generated
```bash
# Verify metrics directory exists
ls -ld /var/cache/elevatediq/metrics/

# Check file permissions
ls -l /var/cache/elevatediq/metrics/*.prom

# Run health check and check metrics
sudo systemctl start elevatediq-runner-health-monitor.service
sleep 3
ls -l /var/cache/elevatediq/metrics/
```

### Logs Not Appearing
```bash
# Verify journald integration
sudo journalctl -u elevatediq-runner-health-monitor.service -n 5

# Check systemd logs
sudo journalctl --unit elevatediq-runner-health-monitor.service --since "1 hour ago"

# Check syslog
sudo tail -20 /var/log/syslog | grep runner-monitor
```

---

## 🔐 Environment Configuration

### Current Settings (on 192.168.168.42)
```bash
# Set in systemd service file
sudo cat /etc/systemd/system/elevatediq-runner-health-monitor.service | grep Environment
```

**Output:**
```
Environment="RUN_MODE=host"
Environment="ALERT_REPO=kushin77/ElevatedIQ-Mono-Repo"
```

### To Modify Environment Variables
```bash
# Edit service file
sudo nano /etc/systemd/system/elevatediq-runner-health-monitor.service

# Reload systemd
sudo systemctl daemon-reload

# Restart timer
sudo systemctl restart elevatediq-runner-health-monitor.timer
```

### To Switch to k8s Mode
```bash
# Edit service file
sudo nano /etc/systemd/system/elevatediq-runner-health-monitor.service

# Change RUN_MODE to:
# Environment="RUN_MODE=k8s"

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart elevatediq-runner-health-monitor.timer
```

---

## 📊 Monitoring & Observability

### Prometheus Metrics
The runner health monitor exports the following metrics to `/var/cache/elevatediq/metrics/`:

**Metric: `runner_health_checks_total`**
- Type: Counter
- Description: Total number of health checks performed
- Labels: `host=192.168.168.42, mode=host`

**Metric: `runner_restarts_total`**
- Type: Counter
- Description: Total number of runner service restarts
- Labels: `host=192.168.168.42, service=<runner-service-name>`

**Metric: `runner_failures_total`**
- Type: Counter
- Description: Total number of failed health checks or restarts
- Labels: `host=192.168.168.42, reason=<failure-reason>`

### Integration with Prometheus
To scrape metrics, add to prometheus.yml:
```yaml
scrape_configs:
  - job_name: 'runner-health-monitor'
    static_configs:
      - targets: ['192.168.168.42:8081']
    scrape_interval: 10s
```

Then start metrics exporter:
```bash
# On 192.168.168.42
python3 /opt/elevatediq/bin/metrics_exporter.py

# Or in background
nohup python3 /opt/elevatediq/bin/metrics_exporter.py > /tmp/metrics_exporter.log 2>&1 &
```

### Querying Metrics
```bash
# Check if exporter is running
curl http://192.168.168.42:8081/metrics

# Filter by metric name
curl http://192.168.168.42:8081/metrics | grep runner_
```

---

## 🔗 Related Components

### GitHub Issues Integration
The monitor creates GitHub issues when runners are offline:
- **Repository:** kushin77/ElevatedIQ-Mono-Repo
- **Issue Template:** Includes runner name, status, logs
- **Label:** `type-alert`, `runner-health`

### GitHub API Authentication
Uses GitHub App JWT tokens (not long-lived tokens):
- Helper script: `/opt/elevatediq/bin/github_app_token.sh`
- Token storage: Vault (secure, no disk storage)
- TTL: 10 minutes

### Vault Integration
For private key storage:
```bash
# Fetch key from Vault
/opt/elevatediq/bin/vault_fetch_key.sh <key-id>

# Script supports:
# - Vault CLI (with auth token)
# - Vault HTTP API (with bearer token)
```

---

## 📝 Log Examples

### Successful Health Check (No Issues)
```
[2026-03-04 18:46:19 UTC] [INFO] Starting runner health check
[2026-03-04 18:46:19 UTC] [INFO] Runner Host: 192.168.168.42
[2026-03-04 18:46:19 UTC] [INFO] Mode: host
[2026-03-04 18:46:20 UTC] [INFO] Queried GitHub API for runner status
[2026-03-04 18:46:21 UTC] [INFO] All runners healthy - no action needed
[2026-03-04 18:46:21 UTC] [INFO] Metrics exported to /var/cache/elevatediq/metrics/
[2026-03-04 18:46:21 UTC] [INFO] Health check completed successfully
```

### Failed Health Check with Recovery
```
[2026-03-04 18:46:19 UTC] [WARN] Runner service not responding
[2026-03-04 18:46:19 UTC] [INFO] Attempting restart...
[2026-03-04 18:46:20 UTC] [SUCCESS] Runner restarted successfully
[2026-03-04 18:46:21 UTC] [INFO] GitHub API confirms runner back online
[2026-03-04 18:46:21 UTC] [INFO] Metrics updated - 1 restart recorded
```

### GitHub Issue Creation
```
[2026-03-04 18:46:19 UTC] [ERROR] Runner 'runner-prod-01' offline for > 5 minutes
[2026-03-04 18:46:20 UTC] [INFO] Creating GitHub issue...
[2026-03-04 18:46:21 UTC] [SUCCESS] Issue #7777 created
[2026-03-04 18:46:21 UTC] [INFO] Issue link: https://github.com/kushin77/ElevatedIQ-Mono-Repo/issues/7777
```

---

## 🚨 Alerts & Escalation

### When to Escalate
- Service fails 3+ times in a row
- Multiple runners offline simultaneously
- GitHub API errors (rate limited, network issues)
- Disk space full in `/var/cache/elevatediq/metrics/`

### Escalation Steps
```bash
# 1. Check service status
sudo systemctl status elevatediq-runner-health-monitor.service

# 2. View recent logs
sudo journalctl -u elevatediq-runner-health-monitor.service -n 100

# 3. Check disk space
df -h /var/cache/elevatediq/

# 4. Manual health check
sudo systemctl start elevatediq-runner-health-monitor.service

# 5. If still failing, check:
bash -n /opt/elevatediq/bin/runner_health_monitor.sh
ls -la /opt/elevatediq/bin/github_app_token.sh
ls -la /opt/elevatediq/bin/vault_fetch_key.sh
```

### Dashboard Links
- **GitHub Issues:** https://github.com/kushin77/ElevatedIQ-Mono-Repo/issues?q=label%3Arunner-health
- **Source Code:** https://github.com/kushin77/ElevatedIQ-Mono-Repo/blob/main/scripts/pmo/runner_health_monitor.sh
- **Deployment Issue:** https://github.com/kushin77/ElevatedIQ-Mono-Repo/issues/7774

---

## 📚 Reference

### Source Code Locations
- **Main Script:** `scripts/pmo/runner_health_monitor.sh`
- **GitHub App Helper:** `scripts/automation/pmo/github_app_token.sh`
- **Vault Helper:** `scripts/automation/pmo/vault_fetch_key.sh`
- **Metrics Exporter:** `scripts/automation/pmo/metrics_exporter.py`
- **Unit Tests:** `scripts/automation/pmo/tests/test_runner_health_monitor*.sh`

### Related Documentation
- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Kubernetes ARC Documentation](https://github.com/actions/actions-runner-controller)
- [Prometheus Metrics Format](https://prometheus.io/docs/instrumenting/exposition_formats/)

### Support
- **PR #7771:** Implementation and deployment tracking
- **Issue #7766:** Epic for runner health monitoring
- **Issue #7774:** Deployment record
- **Epic #7768:** Follow-up work (Spot interruption, image cache)

---

**Last Updated:** 2026-03-04 18:45 UTC
**Operator:** akushnir
**Status:** PRODUCTION READY ✅
