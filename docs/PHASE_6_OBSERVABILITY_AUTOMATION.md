# Phase 6: Observability Auto-Deployment Framework
## Complete Operationalization & Deployment Guide

**Date:** 2026-03-09  
**Status:** 🟢 Production-Ready  
**Architecture:** Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off  

---

## 1. Overview

Phase 6 Observability Framework is now **fully automated** for hands-off deployment:

- ✅ **Immutable:** Append-only JSONL audit logs (no data loss on failures)
- ✅ **Ephemeral:** All credentials fetched at runtime (GSM → Vault → env fallback)
- ✅ **Idempotent:** Safe to re-run; gracefully handles missing prerequisites
- ✅ **No-Ops:** Single command deployment with zero manual steps
- ✅ **Hands-Off:** Runs automatically daily at 01:00 UTC (via systemd timer)
- ✅ **Multi-Layer:** GSM primary → Vault secondary → env tertiary

### Files Deployed

1. **Auto-Deployment Script:** `runners/phase6-observability-auto-deploy.sh`
   - Credential detection and fallback logic
   - Pre-flight validation
   - Deployment orchestration
   - Immutable audit logging
   - Slack/webhook notifications

2. **Systemd Service:** `systemd/phase6-observability-auto-deploy.service`
   - Oneshot execution model
   - Structured logging (journald)
   - Error handling & timeouts

3. **Systemd Timer:** `systemd/phase6-observability-auto-deploy.timer`
   - Daily execution at 01:00 UTC
   - Persistent scheduling (survives reboots)
   - Boot-time execution (5min delay if system offline)

---

## 2. Installation & Configuration

### Step A: Admin Installation (One-Time)

```bash
# 1. Copy systemd units to system directory
sudo cp systemd/phase6-observability-auto-deploy.* /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/phase6-observability-auto-deploy.*

# 2. Reload systemd daemon
sudo systemctl daemon-reload

# 3. Enable and start timer (runs daily at 01:00 UTC)
sudo systemctl enable --now phase6-observability-auto-deploy.timer

# 4. Verify installation
sudo systemctl list-timers phase6-observability-auto-deploy.timer --no-pager
sudo systemctl status phase6-observability-auto-deploy.timer
```

### Step B: Configure Credentials (Choose One)

Configure credentials in ONE of these three backends:

**Option 1: Google Secret Manager (GSM)**
- Create secrets: `prom-host`, `grafana-host`, `grafana-api-token`
- Set env: `SECRETS_BACKEND=gsm`, `GSM_PROJECT=your-project-id`
- Systemd will auto-fetch on each run

**Option 2: HashiCorp Vault**
- Create KV secrets: `secret/prom-host`, `secret/grafana-host`, `secret/grafana-api-token`
- Set env: `SECRETS_BACKEND=vault`, `VAULT_ADDR=https://vault.example.com:8200`
- Systemd will auto-fetch with stored credentials

**Option 3: Environment Variables (Fastest)**
- Set env: `SECRETS_BACKEND=env`
- Set: `PROM_HOST_ENV`, `GRAFANA_HOST_ENV`, `GRAFANA_TOKEN_ENV`
- Systemd will use values directly

### Step C: Apply Configuration

```bash
# Create override directory
sudo mkdir -p /etc/systemd/system/phase6-observability-auto-deploy.service.d

# Create override config with your backend choice
sudo tee /etc/systemd/system/phase6-observability-auto-deploy.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment="SECRETS_BACKEND=gsm"
Environment="GSM_PROJECT=your-gcp-project-id"
# OR for Vault:
# Environment="SECRETS_BACKEND=vault"
# Environment="VAULT_ADDR=https://vault.example.com:8200"
# OR for env vars:
# Environment="SECRETS_BACKEND=env"
# Environment="PROM_HOST_ENV=prometheus.example.com"
# Environment="GRAFANA_HOST_ENV=https://grafana.example.com:3000"
# Environment="GRAFANA_TOKEN_ENV=your-grafana-token"
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart phase6-observability-auto-deploy.timer
```

---

## 3. Verification & Testing

### Verify Installation

```bash
# Check timer status
sudo systemctl status phase6-observability-auto-deploy.timer

# View next execution time
sudo systemctl list-timers phase6-observability-auto-deploy.timer --no-pager

# Check systemd logs
sudo journalctl -u phase6-observability-auto-deploy.timer -n 50 --no-pager
```

### Manual Test Run

```bash
# Execute deployment manually
/usr/bin/env bash /home/akushnir/self-hosted-runner/runners/phase6-observability-auto-deploy.sh

# With debug output
DEBUG=1 /usr/bin/env bash /home/akushnir/self-hosted-runner/runners/phase6-observability-auto-deploy.sh
```

---

## 4. Audit Trail & Monitoring

### Immutable Audit Logs

```bash
# View all Phase 6 deployment attempts
tail -100 logs/phase6-observability-audit.jsonl | jq '.'

# Filter by status
cat logs/phase6-observability-audit.jsonl | jq 'select(.status == "SUCCESS")'

# View performance metrics
cat logs/phase6-observability-audit.jsonl | jq '.[] | {timestamp, event, duration_ms, rc}'
```

### Systemd Journal Logs

```bash
# View service execution logs
sudo journalctl -u phase6-observability-auto-deploy.service -n 100 --no-pager

# Follow real-time logs (useful during 01:00 UTC execution)
sudo journalctl -u phase6-observability-auto-deploy.service -f

# Count successful deployments
cat logs/phase6-observability-audit.jsonl | jq 'select(.status == "SUCCESS")' | wc -l
```

---

## 5. Operational Workflow

### First-Time Deployment
1. Run steps in Section 2.A (admin install)
2. Run steps in Section 2.B-C (configure credentials)
3. Verify in Section 3 (manual test run)
4. Wait for 01:00 UTC automatic execution, or test manually

### Daily Operations
1. Timer triggers automatically at 01:00 UTC
2. Script fetches credentials from configured backend
3. Deployment runs with idempotent provisioning
4. Audit logged immutably to JSONL
5. Slack notification sent (if webhook configured)
6. **No manual steps required**

### Credential Rotation
Credentials are fetched at runtime, so just update your backend:
- GSM: `gcloud secrets versions add prom-host --data-file=...`
- Vault: `vault kv put secret/prom-host value=...`
- Env: Update environment variables in systemd override

Script automatically picks up new values on next execution.

---

## 6. Architecture Verification

### ✅ Immutability
- Append-only JSONL audit log (no modifications post-write)
- Git commits immutable (SHA-1 versioning)
- Systemd units versioned and tracked

### ✅ Ephemeralness
- All credentials fetched at runtime (never embedded)
- Multi-layer fallback: GSM → Vault → env
- Credentials exist only during execution window

### ✅ Idempotency
- Script handles missing prerequisites gracefully
- Deployment steps skip if already completed
- Credential fallback continues even if some backends unavailable
- Multiple simultaneous executions supported

### ✅ No-Ops
- Single admin install command (Section 2.A)
- Automatic timer-based execution (no cron, no manual triggering)
- Zero manual steps after credential setup
- Graceful error handling without user intervention

### ✅ Hands-Off
- Deploy once, runs forever
- Self-healing on retry (next timer execution)
- Credential updates transparently picked up
- Audit + Slack notifications for ops visibility

---

## 7. Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Timer not running | Service not enabled | `sudo systemctl enable --now phase6-...timer` |
| Credential errors | Backend misconfigured | Verify GSM_PROJECT, VAULT_ADDR, or env vars |
| Deployment incomplete | Required credentials missing | Ensure prom-host, grafana-host set in chosen backend |
| Script failures | Missing tools (jq, gcloud, vault) | Install: `sudo apt-get install jq` |
| No audit logs | Log directory missing | `mkdir -p logs/` |
| Slack notifications fail | Webhook not configured | Set SLACK_WEBHOOK env in systemd override |

---

## 8. Advanced Configuration

### Slack Notifications

```bash
# Add webhook to systemd override
sudo tee -a /etc/systemd/system/phase6-observability-auto-deploy.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment="SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
EOF

sudo systemctl daemon-reload
```

### Custom Execution Interval

```bash
# Edit timer to change schedule (from daily 01:00 UTC)
sudo systemctl edit phase6-observability-auto-deploy.timer

# Example: Run every 4 hours
# [Timer]
# OnCalendar=*-*-* 00,04,08,12,16,20:00:00
```

### Override Target Hosts

```bash
# Run with custom deployment targets
export PROM_HOST=custom-prometheus.example.com
export GRAFANA_HOST=custom-grafana.example.com
/usr/bin/env bash /home/akushnir/self-hosted-runner/runners/phase6-observability-auto-deploy.sh
```

---

## 9. Support & Documentation

- **Framework:** `OBSERVABILITY_DEPLOYMENT_FRAMEWORK_COMPLETE_2026_03_09.md`
- **Deploy Runbook:** `docs/DEPLOY_OBSERVABILITY_RUNBOOK.md`
- **Setup Guide:** `docs/COMPLETE_OBSERVABILITY_SETUP_GUIDE.md`
- **GitHub Issues:** #2156 (deployment), #2153 (operator input)

---

## 🎯 Summary

Phase 6 Observability is **fully automated**:

✅ Auto-deployment script (credential fallback, audit logging)  
✅ Systemd timer (daily 01:00 UTC, persistent)  
✅ Multi-backend credential support (GSM → Vault → env)  
✅ Immutable audit trail (append-only JSONL)  
✅ Zero manual steps post-installation  
✅ Production-ready & hands-off  

**Next Step:** Install systemd units (Section 2.A) and configure credentials (Section 2.B-C). Phase 6 will deploy automatically.
