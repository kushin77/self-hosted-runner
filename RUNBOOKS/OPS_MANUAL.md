# NexusShield Operations Manual
**Status:** Production Ready  
**Last Updated:** 2026-03-11  
**Audience:** Infrastructure Team, On-Call Engineers, SREs

---

## Quick Start

### Service Status Check
```bash
# SSH to production host
ssh akushnir@192.168.168.42

# Check all services
systemctl is-active cloudrun.service redis-worker.service rotate_audit.timer

# Health check
curl http://localhost:8080/health

# Metrics
curl http://localhost:8080/metrics
```

### Emergency Restart
```bash
# Restart all services
sudo systemctl restart cloudrun.service redis-worker.service

# View logs
sudo journalctl -u cloudrun.service -f  # Flask API logs
sudo journalctl -u redis-worker.service -f  # Redis worker logs
sudo journalctl -u rotate_audit.timer -f  # Audit rotation logs
```

---

## 1. Service Inventory

### Core Services (Systemd)

#### `cloudrun.service` — Flask Migration API
- **Purpose:** HTTP API for migration jobs, health checks, metrics
- **Type:** System service (enabled, auto-start on reboot)
- **Runtime:** Python 3.12, gunicorn (3 workers)
- **Port:** 8080 (localhost, no external binding by default)
- **Config:** `/etc/systemd/system/cloudrun.service`
- **Health Endpoint:** `http://localhost:8080/health` → Returns `OK`
- **Metrics Endpoint:** `http://localhost:8080/metrics` → Prometheus format

**Key Paths:**
- Code: `/opt/nexusshield/scripts/cloudrun/`
- Audit log: `BASE64_BLOB_REDACTED-migrate-audit.jsonl`
- Logs: `journalctl -u cloudrun.service`

**Restart Procedure:**
```bash
sudo systemctl restart cloudrun.service
systemctl is-active cloudrun.service  # Verify
curl http://localhost:8080/health  # Smoke test
```

**Scaling:**
- Adjust gunicorn workers in `cloudrun.service` `ExecStart` (default: 3)
- Recommended: 2-4 workers per vCPU for migration workloads

---

#### `redis-worker.service` — Async Job Queue
- **Purpose:** Background job processing (migrations, dry runs)
- **Type:** System service (enabled, auto-start on reboot)
- **Runtime:** Python 3.12, RQ worker
- **Connection:** Redis localhost:6379 (with GSM authentication)
- **Config:** `/etc/systemd/system/redis-worker.service`

**Key Paths:**
- Code: `/opt/nexusshield/scripts/cloudrun/redis_worker.py`
- Logs: `journalctl -u redis-worker.service`

**Restart Procedure:**
```bash
sudo systemctl restart redis-worker.service
systemctl is-active redis-worker.service  # Verify
```

**Queue Monitoring:**
```bash
# Connect to Redis (requires REDIS_PASSWORD from GSM)
redis-cli -p 6379 -a "${REDIS_PASSWORD}"

# View queue stats
rq info

# Inspect queued jobs
rq jobs

# Monitor job processing
rq worker
```

---

#### `rotate_audit.timer` — Daily Audit Rotation
- **Purpose:** Rotate immutable audit logs to GCS daily at 03:30 UTC
- **Type:** Systemd timer (enabled, auto-start on reboot)
- **Schedule:** Daily at 03:30 UTC
- **Executor:** `rotate_audit.service` (oneshot)
- **Config:** 
  - `/etc/systemd/system/rotate_audit.timer`
  - `/etc/systemd/system/rotate_audit.service`

**Key Paths:**
- Script: `/opt/nexusshield/scripts/ops/rotate_audit.sh`
- GCS bucket: `nexusshield-audit-archive`
- Logs: `journalctl -u rotate_audit.service`

**Manual Rotation (if needed):**
```bash
# Run audit rotation immediately
sudo systemctl start rotate_audit.service

# Wait for completion
sudo systemctl status rotate_audit.service

# Verify archival
bash /opt/nexusshield/scripts/ops/verify_audit_archival.sh
```

**Schedule Management:**
```bash
# View timer schedule
systemctl list-timers rotate_audit.timer

# Modify schedule (edit timer unit)
sudo systemctl edit rotate_audit.timer
sudo systemctl daemon-reload
sudo systemctl restart rotate_audit.timer
```

---

## 2. Immutable Audit Trail

### Understanding the Audit Log

**Location:** `BASE64_BLOB_REDACTED-migrate-audit.jsonl`

**Format:** JSONL (one JSON object per line) with SHA256 chaining
```json
{
  "prev": "hash_of_previous_entry",
  "hash": "sha256_hash_of_current_entry",
  "entry": {
    "event": "job_queued|dry_run_start|dry_run_validation|dry_run_completed|...",
    "job_id": "uuid",
    "status": "ok|failed|...",
    "ts": "ISO8601_timestamp"
  }
}
```

**Integrity Verification:**
```bash
# Run verification script
bash /opt/nexusshield/scripts/ops/verify_audit_archival.sh

# Manual verification (Python)
python3 << 'EOF'
import json
import hashlib

with open('BASE64_BLOB_REDACTED-migrate-audit.jsonl') as f:
    prev_hash = None
    for i, line in enumerate(f, 1):
        entry = json.loads(line)
        if prev_hash and entry['prev'] != prev_hash:
            print(f"CHAIN BREAK at line {i}: expected {prev_hash}, got {entry['prev']}")
            break
        prev_hash = entry['hash']
    else:
        print(f"✓ Audit chain verified ({i} entries, all linked)")
EOF
```

### Audit Rotation Details

**Daily Rotation (Automated):**
1. **Timer triggers:** 03:30 UTC daily (via `rotate_audit.timer`)
2. **Service runs:** `rotate_audit.service` executes `rotate_audit.sh`
3. **Script actions:**
   - Rotates local audit file to timestamped archive
   - Starts new audit log file
   - Uploads archived file to GCS bucket `nexusshield-audit-archive`
4. **Archival:** GCS bucket preserves all rotated logs (immutable, versioned)

**Log Locations:**
- **Active:** `BASE64_BLOB_REDACTED-migrate-audit.jsonl`
- **Rotated (local):** `BASE64_BLOB_REDACTED-migrate-audit.YYYY-MM-DD.jsonl`
- **Archived (GCS):** `gs://nexusshield-audit-archive/portal-migrate-audit.YYYY-MM-DD.jsonl`

**Manual Archive Operations:**
```bash
# List archived files in GCS
gsutil ls gs://nexusshield-audit-archive/

# Download a specific archive
gsutil cp gs://nexusshield-audit-archive/portal-migrate-audit.2026-03-11.jsonl .

# View archive contents
gsutil cat gs://nexusshield-audit-archive/portal-migrate-audit.2026-03-11.jsonl | tail -10
```

---

## 3. Secrets Management

### GSM (Google Secret Manager) Setup

All production credentials are stored in GSM. The system uses fallback chain: **GSM → Vault KVv2 → AWS Secrets Manager → Environment**

**Active Secrets (GSM Project: `nexusshield-prod`):**

| Secret Name | Purpose | Rotation Policy |
|-------------|---------|-----------------|
| `portal-mfa-secret` | MFA token signing | Manual (every 90 days) |
| `runner-redis-password` | Redis authentication | Manual (every 90 days) |
| `portal-db-connection` | Database connection string | Manual (on schema changes) |
| `grafana-url` | Grafana API endpoint | Manual (on Grafana move) |
| `grafana-api-key` | Grafana API authentication | Auto-rotate (Grafana settings) |

**Retrieving a Secret:**
```bash
# Fetch from GSM
gcloud secrets versions access latest --secret="portal-mfa-secret" --project="nexusshield-prod"

# Use in scripts
SECRET=$(gcloud secrets versions access latest --secret="portal-redis-password" --project="nexusshield-prod")
export REDIS_PASSWORD="$SECRET"
```

**Adding a New Secret:**
```bash
# Create secret
echo "secret_value" | gcloud secrets create new-secret \
  --data-file=- \
  --project="nexusshield-prod" \
  --replication-policy="user-managed" \
  --locations="us-central1"

# Update existing secret
echo "new_secret_value" | gcloud secrets versions add portal-mfa-secret \
  --data-file=- \
  --project="nexusshield-prod"
```

**Vault Fallback (Optional):**
If GSM is unavailable, the system falls back to Vault KVv2:
```bash
# Authenticate to Vault
vault login -token-only -method=token

# Fetch secret
vault kv get secret/nexusshield/portal-mfa-secret
```

---

## 4. Monitoring & Alerting

### Prometheus Metrics

**Metrics Endpoint:** `http://localhost:8080/metrics`

**Key Metrics:**

| Metric | Type | Description |
|--------|------|-------------|
| `nexusshield_http_requests_total{status=200,...}` | Counter | Total HTTP requests by status code |
| `nexusshield_jobs_total{event="queued\|started\|completed\|failed"}` | Counter | Job lifecycle events |
| `nexusshield_job_duration_seconds{quantile="0.5\|0.95\|0.99"}` | Histogram | Job duration percentiles |
| `process_resident_memory_bytes` | Gauge | Memory usage |
| `python_gc_collections_total` | Counter | GC collections |

**Scraping (Prometheus Server):**
```yaml
# In prometheus.yaml
scrape_configs:
  - job_name: 'nexusshield'
    static_configs:
      - targets: ['192.168.168.42:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s
    scrape_timeout: 10s
```

**Querying:**
```bash
# Connect to Prometheus
curl http://prometheus-server:9090/api/v1/query?query=nexusshield_jobs_total

# PromQL examples
# Job completion rate
rate(nexusshield_jobs_total{event="completed"}[5m])

# Error rate
rate(nexusshield_http_requests_total{status=~"5.."}[5m])

# Job latency (p99)
histogram_quantile(0.99, nexusshield_job_duration_seconds)
```

### Alert Rules

**Location:** `monitoring/alerts/nexusshield.rules.yaml`

**Deployment:**
```bash
# Deploy alert rules to cluster (requires kubectl)
bash /opt/nexusshield/scripts/ops/deploy_alerts.sh
```

**Alert Definitions:**

1. **NexusShieldHighErrorRate** (severity: page)
   - Condition: Error rate > 5% over 5 minutes
   - Action: Page on-call immediately

2. **NexusShieldLongJobDuration** (severity: ticket)
   - Condition: p95 job duration > 30s over 10 minutes
   - Action: Create ops ticket for investigation

3. **NexusShieldJobCompletionFailures** (severity: ticket)
   - Condition: No job lifecycle events over 15 minutes
   - Action: Page on-call (service likely down)

**Testing Alert Firing:**
```bash
# Trigger error rate alert (simulate errors)
for i in {1..50}; do
  curl -X POST http://localhost:8080/api/v1/migrate -H "Invalid-Auth: test" &
done
wait

# Monitor metrics
while true; do
  curl -s http://localhost:8080/metrics | grep nexusshield_http_requests_total
  sleep 5
done
```

### Grafana Dashboard

**Dashboard JSON:** `dashboards/nexusshield.json`

**Provisioning (Fully Automated):**
```bash
# Step 1: Auto-provision Grafana credentials to GSM
bash /opt/nexusshield/scripts/ops/provision_grafana_credentials.sh

# Step 2: Import dashboard to Grafana
bash /opt/nexusshield/scripts/ops/import_grafana_dashboard.sh

# Optional: Override with real Grafana credentials
export GRAFANA_URL="https://grafana.example.com"
export GRAFANA_API_KEY="glsa_abc123..."
bash /opt/nexusshield/scripts/ops/provision_grafana_credentials.sh
bash /opt/nexusshield/scripts/ops/import_grafana_dashboard.sh
```

**Dashboard Panels:**
- HTTP Request Rate
- Job Completion Rate
- Job Duration Distribution
- Redis Queue Depth
- System Memory/CPU
- Alert Status
- Runbook Links

---

## 5. Incident Response

### Service Down (cloudrun.service)

**Detection:** Health endpoint unreachable or /metrics returns errors

**Response:**
```bash
# 1. Check service status
sudo systemctl status cloudrun.service

# 2. View recent logs
sudo journalctl -u cloudrun.service -n 50

# 3. Check for disk space issues
df -h /opt/nexusshield/

# 4. Restart service
sudo systemctl restart cloudrun.service

# 5. Verify health
curl http://localhost:8080/health

# 6. Check metrics
curl http://localhost:8080/metrics | head -20
```

**If restart fails:**
```bash
# Check systemd unit configuration
sudo cat /etc/systemd/system/cloudrun.service

# Verify Python environment
python3 --version
which python3

# Check Redis connectivity
redis-cli -p 6379 ping

# Check GSM credentials
gcloud auth list
gcloud config get-value project
```

### High Error Rate (> 5%)

**Alerting:** Alert rule `NexusShieldHighErrorRate` fires

**Investigation:**
```bash
# 1. Check recent audit entries for errors
tail -20 BASE64_BLOB_REDACTED-migrate-audit.jsonl | \
  jq 'select(.entry.event | contains("error") or .entry.status == "failed")'

# 2. Check Prometheus for error patterns
curl http://prometheus:9090/api/v1/query?query=\
  'rate(nexusshield_http_requests_total{status=~"5.."}[5m])'

# 3. Review logs
sudo journalctl -u cloudrun.service -n 100 | grep -i error

# 4. Verify client requests (if auth errors)
tail -20 BASE64_BLOB_REDACTED-migrate-audit.jsonl | \
  jq 'select(.entry.event == "auth_failed")'
```

**Resolution:**
- If GSM unavailable: Check GCP permissions and service account auth
- If database connectivity: Verify database connection string in GSM
- If Redis queue: Check Redis service status and password rotation

### Audit Trail Corruption

**Detection:** Audit chain verification fails (`verify_audit_archival.sh` reports breaks)

**Response (CRITICAL):**
```bash
# 1. Stop all services immediately
sudo systemctl stop cloudrun.service redis-worker.service

# 2. Preserve corrupted audit file for forensics
cp BASE64_BLOB_REDACTED-migrate-audit.jsonl \
   /var/backup/portal-migrate-audit.CORRUPTION.$(date +%s).jsonl

# 3. Retrieve last known-good archive from GCS
gsutil cp gs://nexusshield-audit-archive/portal-migrate-audit.2026-03-10.jsonl \
  BASE64_BLOB_REDACTED-migrate-audit.jsonl

# 4. Restart services
sudo systemctl start redis-worker.service cloudrun.service

# 5. Verify integrity
bash /opt/nexusshield/scripts/ops/verify_audit_archival.sh

# 6. File incident report
# Include: timestamp of corruption discovered, last-known-good entry, scope of data loss
```

---

## 6. Scaling & Performance

### Vertical Scaling (Current Host)

**Increasing Worker Count:**
```bash
# Edit cloudrun service
sudo systemctl edit cloudrun.service

# Find ExecStart line, modify:
# ExecStart=/usr/bin/gunicorn --workers 5 --bind 0.0.0.0:8080 app:app
#                               ↑ increase from 3 to 5

sudo systemctl daemon-reload
sudo systemctl restart cloudrun.service
```

**Recommended Settings:**
- Workers: 2-8 (2 × vCPU count typical)
- Threads: 1 (Flask default, increase only if CPU-bound)
- Timeout: 120s (allow long migrations)
- Max requests: 1000 (periodic worker recycle)

### Horizontal Scaling (Multi-Host)

For high-volume deployments:
1. Set up second host (same setup via `scripts/deploy/deploy_to_staging.sh`)
2. Point Redis to shared Redis cluster (instead of localhost)
3. Deploy load balancer (nginx, HAProxy) in front of both hosts
4. Scale audit rotation: use Cloud Storage (GCS) for distributed rotation

---

## 7. Backup & Recovery

### Audit Log Backup Strategy

**Primary:** Daily rotation to GCS (automated)  
**Secondary:** Periodic exports to long-term storage (recommended weekly)

**Manual Export:**
```bash
# Export all audit logs from GCS to local archive
gsutil -m cp gs://nexusshield-audit-archive/*.jsonl /backup/audit-export/

# Create tarball for offline storage
tar -czf nexusshield-audit-export-$(date +%Y%m%d).tar.gz /backup/audit-export/

# Verify tarball integrity
tar -tzf nexusshield-audit-export-$(date +%Y%m%d).tar.gz | wc -l
```

### Service State Recovery

**Redis Jobs Queue:**
- Jobs are persisted in Redis (RDB snapshots)
- If Redis is lost, in-flight jobs must be re-queued
- Audit trail is preserved (no data loss, only operational delay)

**Flask Application State:**
- Stateless (no persistent state)
- Restart immediately recovers full functionality
- Health endpoint indicates readiness

**Config Recovery:**
```bash
# All production configuration is in:
# 1. systemd units: /etc/systemd/system/
# 2. Scripts: /opt/nexusshield/scripts/
# 3. Secrets: Google Secret Manager (GSM)

# Restore from fresh host:
git clone https://github.com/kushin77/self-hosted-runner.git
bash scripts/deploy/deploy_to_staging.sh  # (or to prod with PROD=1)
```

---

## 8. Security Operations

### Credential Rotation

**Manual Rotation Schedule (Recommended):**
- MFA secret: Every 90 days
- Redis password: Every 90 days  
- Grafana API key: Auto-rotate in Grafana settings (30 days typical)
- Database connection: On schema/permission changes

**Rotation Procedure:**
```bash
# 1. Generate new credential (example: MFA secret)
openssl rand -hex 32

# 2. Update GSM (adds new version, keeps history)
echo "new_secret_value" | gcloud secrets versions add portal-mfa-secret \
  --data-file=- --project="nexusshield-prod"

# 3. Restart services to pick up new version
sudo systemctl restart cloudrun.service redis-worker.service

# 4. Verify in audit trail
tail -10 BASE64_BLOB_REDACTED-migrate-audit.jsonl
```

### Security Audit

**Monthly Security Checklist:**
```bash
# 1. Verify service health
systemctl is-active cloudrun.service redis-worker.service rotate_audit.timer

# 2. Audit trail integrity
bash /opt/nexusshield/scripts/ops/verify_audit_archival.sh

# 3. GSM secret versions (check for orphaned versions)
gcloud secrets list --project="nexusshield-prod"
gcloud secrets versions list portal-mfa-secret --project="nexusshield-prod"

# 4. Check systemd unit permissions
stat /etc/systemd/system/cloudrun.service
stat /opt/nexusshield/scripts/cloudrun/

# 5. Verify no plaintext secrets in logs
grep -r "SECRET\|PASSWORD\|KEY" /var/log/ | grep -v "GSM\|VAULT" || echo "✓ Clean"

# 6. Review recent audit entries
tail -100 BASE64_BLOB_REDACTED-migrate-audit.jsonl | \
  jq '.entry.event' | sort | uniq -c
```

### Compliance & Audit

**Data Retention:**
- Audit logs: Retained indefinitely (immutable, compliance-safe)
- GCS archival: Standard storage class (no auto-delete)
- Job queue: In-memory (ephemeral, cleaned up after completion)

**Audit Log Exports (for compliance):**
```bash
# Export for SOC 2 / ISO 27001 audits
gsutil -m cp gs://nexusshield-audit-archive/*.jsonl audit-export/
tar -czf audit-export-$(date +%Y-%m-%d).tar.gz audit-export/

# Generate summary report
cat audit-export/*.jsonl | \
  jq -r '[.entry.event, .entry.ts]' | \
  sort | \
  uniq -c > audit-summary.txt
```

---

## 9. Glossary & References

| Term | Definition |
|------|-----------|
| **Immutable Audit Trail** | Append-only JSONL with SHA256 chaining; no entries can be modified or deleted |
| **Ephemeral Services** | Containers/processes that start fresh; no persistent state (except audit) |
| **Idempotent Deployment** | All scripts safe to run repeatedly without side effects |
| **GSM** | Google Secret Manager (primary credential store) |
| **RQ** | Resilient Queue (Redis-backed job queue) |
| **Systemd** | Linux init system for managing services |

**Key Documents:**
- [FINAL_PRODUCTION_LIVE_SIGN_OFF_2026_03_11.md](../FINAL_PRODUCTION_LIVE_SIGN_OFF_2026_03_11.md) — Complete deployment status
- [RUNBOOKS/alerts_nexusshield.md](./alerts_nexusshield.md) — Alert definitions & response procedures
- [dashboards/nexusshield.json](../dashboards/nexusshield.json) — Grafana dashboard configuration

**Support Contacts:**
- Primary: akushnir@nexusshield.local
- Backup: observability-team@nexusshield.local
- Escalation: platform-leadership@nexusshield.local

---

## 10. Appendix: Common Commands

```bash
# Service management
systemctl status cloudrun.service                      # Check status
sudo systemctl restart cloudrun.service                # Restart service
sudo journalctl -u cloudrun.service -f                 # Follow logs
sudo journalctl -u cloudrun.service --since "2h ago"   # Last 2 hours

# Health checks
curl http://localhost:8080/health                      # API health
curl http://localhost:8080/metrics | head -30          # Prometheus metrics
curl http://localhost:8080/api/v1/migrate -X OPTIONS   # CORS check

# Audit operations
tail -20 BASE64_BLOB_REDACTED-migrate-audit.jsonl  # Recent entries
grep '"event": "auth_failed"' BASE64_BLOB_REDACTED-migrate-audit.jsonl | wc -l  # Auth failures
bash /opt/nexusshield/scripts/ops/verify_audit_archival.sh                   # Verify chain

# Redis queue
redis-cli -p 6379 -a "$REDIS_PASSWORD" INFO stats    # Queue stats
redis-cli -p 6379 -a "$REDIS_PASSWORD" KEYS "*"      # List queue keys
redis-cli -p 6379 -a "$REDIS_PASSWORD" FLUSHDB        # Clear queue (⚠️ CAUTION)

# GCS audit archive
gsutil ls gs://nexusshield-audit-archive/           # List archives
gsutil cat gs://nexusshield-audit-archive/portal-migrate-audit.2026-03-11.jsonl | tail -5  # View archive
gsutil cp gs://nexusshield-audit-archive/portal-migrate-audit.2026-03-11.jsonl .  # Download

# Secrets
gcloud secrets list --project="nexusshield-prod"    # List all secrets
gcloud secrets versions list portal-mfa-secret --project="nexusshield-prod"  # View versions
gcloud secrets versions access latest --secret="portal-mfa-secret" --project="nexusshield-prod"  # Get secret
```

---

**END OF OPS MANUAL**

*For questions or updates, file issues at: https://github.com/kushin77/self-hosted-runner/issues*
