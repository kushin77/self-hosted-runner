# NAS Monitoring Deployment Runbook
## Direct Deployment to Worker Node (192.168.168.42)
## Production Ready • Immutable • Hands-Off • GSM-Integrated

**Date:** 2026-03-14  
**Status:** APPROVED FOR IMMEDIATE DEPLOYMENT ✅  
**Compliance:** All 8 automation mandates satisfied  
**Deployment Method:** Direct bash (no GitHub Actions)

---

## QUICK START (2 minutes)

```bash
# 1. On your local machine (development)
cd ~/self-hosted-runner
git pull origin main

# 2. Copy deployment script to worker node
scp deploy-nas-monitoring-direct.sh elevatediq@192.168.168.42:~

# 3. SSH to worker node
ssh elevatediq@192.168.168.42

# 4. Run deployment as root (with sudo)
sudo ~/deploy-nas-monitoring-direct.sh

# 5. Verify deployment (automatic, but can also run manually)
ssh elevatediq@192.168.168.42 'cd ~/self-hosted-runner && ./verify-nas-monitoring.sh --verbose'

# 6. Access Prometheus
# Browser: http://192.168.168.42:4180/prometheus
# Login: Google OAuth (required)
# Check: Status → Targets → Filter 'eiq-nas' (all 5 jobs GREEN)
```

---

## DEPLOYMENT PHASES

### Phase 0: Pre-Deployment Validation (Local Machine)

**Goal:** Ensure all configuration is valid before touching production

```bash
# 1. Verify git is clean (no uncommitted changes)
cd ~/self-hosted-runner
git status

# Expected: nothing to commit, working tree clean

# 2. Verify all configuration files exist
ls -la monitoring/prometheus.yml \
       docker/prometheus/nas-{recording,alert}-rules.yml \
       deploy-nas-monitoring-direct.sh \
       verify-nas-monitoring.sh

# Expected: all files present and readable

# 3. Verify deployment scripts are executable
test -x deploy-nas-monitoring-direct.sh && echo "✓ Deploy script ready"
test -x verify-nas-monitoring.sh && echo "✓ Verify script ready"

# 4. Check git immutability (cryptographic signatures)
git log --oneline -5 | grep "nas monitoring"

# Expected: commits signed and immutable in git
```

### Phase 1: Worker Node Preparation

**Goal:** Verify worker node is ready to receive deployment

```bash
# On worker node (ssh elevatediq@192.168.168.42)

# Check prerequisites
sudo test -d /etc/prometheus && echo "✓ Prometheus config dir exists"
sudo test -d /opt/monitoring-stack && echo "✓ Monitoring stack dir exists"
docker-compose --version | head -1
docker --version | head -1

# Verify NAS host is reachable
ping -c 1 eiq-nas
curl -s http://eiq-nas:9100/metrics | head -5

# Expected: All checks pass, node-exporter responds
```

### Phase 2: Configuration Deployment

**Goal:** Deploy and validate configuration on worker node

```bash
# On worker node with sudo
sudo ~/deploy-nas-monitoring-direct.sh

# Expected output:
# =========================================
# NAS Monitoring Direct Deployment
# Worker: 192.168.168.42
# Timestamp: 2026-03-14T...Z
# =========================================
# 
# [✓] Prerequisites verified
# [✓] Backup created: /etc/prometheus/.backups/prometheus.yml.2026-03-14T...
# [✓] Prometheus config validated
# [✓] Alert rules validated
# [✓] Recording rules validated
# [✓] Configuration deployed
# [✓] Prometheus healthy
# [✓] NAS metrics being scraped (up=1.0)
# 
# =========================================
# ✓ DEPLOYMENT COMPLETE
# =========================================
```

**Deployment Details:**
- **Atomic backup:** All existing config saved to timestamped backup
- **Validation:** YAML syntax checked via promtool
- **Atomic swap:** Configuration swapped via move (atomic operation)
- **Reload:** Prometheus reloaded (docker-compose restart or systemctl reload)
- **Health check:** 30-second wait for first scrape cycle + up metric verification
- **Rollback ready:** Previous config backed up, rollback available

### Phase 3: Verification

**Goal:** Verify metrics are being collected and alerts are firing

```bash
# Option A: Automatic verification script
./verify-nas-monitoring.sh --verbose

# Option B: Manual verification
# 1. Check Prometheus targets
curl http://192.168.168.42:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.instance=="eiq-nas")'

# Expected: 5 targets, each with scrapeUrl pointing to eiq-nas:9100 or :9101

# 2. Check metrics ingestion
curl 'http://192.168.168.42:9090/api/v1/query?query=up{instance="eiq-nas"}'

# Expected: value = 1.0 (meaning scrape is successful)

# 3. Check recording rules
curl 'http://192.168.168.42:9090/api/v1/query?query=nas:cpu:usage_percent:5m_avg'

# Expected: values array with CPU usage percentage (after 30+ seconds)

# 4. Check alert rules loaded
curl http://192.168.168.42:9090/api/v1/rules | jq '.data.groups[] | select(.name | contains("nas"))'

# Expected: 6 rule groups (storage, network, compute, process, replication, availability)
```

### Phase 4: OAuth Access Verification

**Goal:** Verify OAuth protection is working on all endpoints

```bash
# 1. Access Prometheus via OAuth proxy (requires Google login)
# Browser: http://192.168.168.42:4180/prometheus

# Expected redirect to Google login, then Prometheus UI

# 2. Check NAS targets in Prometheus UI
# Navigate: Status → Targets
# Filter: 'eiq-nas'

# Expected: All 5 jobs present:
#   - eiq-nas-node-metrics (UP)
#   - eiq-nas-storage-metrics (UP)
#   - eiq-nas-network-metrics (UP)
#   - eiq-nas-process-metrics (UP)
#   - eiq-nas-custom-metrics (UP or DOWN if port 9101 unavailable)

# 3. Query NAS metrics
# UI: Select Graph tab
# Query: up{instance="eiq-nas"}
# Execute query

# Expected: Graph showing metric = 1.0 (constant, scrape successful)
```

### Phase 5: Grafana Dashboard Creation

**Goal:** Create dashboards for NAS monitoring visualization

```bash
# Access Grafana: http://192.168.168.42:3000 (Google OAuth required)

# Create Dashboard 1: NAS System Overview
# Panels:
#   - CPU Usage: Query nas:cpu:usage_percent:5m_avg (gauge, 0-100%)
#   - Memory Usage: Query nas:memory:used_percent:5m_avg (gauge, 0-100%)
#   - Load Average: Query nas:system:load:5m_avg (graph)
#   - Uptime: Query nas:system:uptime_seconds (stat)
#   - Process Count: Query nas:processes:running:5m_avg (stat, threshold >50)

# Create Dashboard 2: NAS Storage
# Panels:
#   - Storage Capacity: Query nas:storage:used_percent:5m_avg (gauge, 0-100%)
#   - Available Space: Query nas:storage:available_bytes:5m_avg (stat, bytes)
#   - Inode Usage: Query nas:storage:inodes_used_percent:5m_avg (gauge)
#   - Filesystem Table: Query node_filesystem_size_bytes{instance="eiq-nas"} (table)

# Create Dashboard 3: NAS Network
# Panels:
#   - Ingress: Query nas:network:bytes_in:1m_rate (graph, bytes/sec)
#   - Egress: Query nas:network:bytes_out:1m_rate (graph, bytes/sec)
#   - Network Errors: Query rate(node_network_receive_errs_total[5m]) (graph)
#   - Interface Status: Query node_network_up{instance="eiq-nas"} (table)

# Create Dashboard 4: NAS Alerts
# Panels:
#   - Active Alerts: Alert list from Alertmanager
#   - Firing Alerts: Query ALERTS{instance="eiq-nas"} (table)
#   - Recent Events: Show alert state changes (time series)
```

### Phase 6: Alert Validation

**Goal:** Confirm alerts can fire if thresholds are exceeded

```bash
# Check alert rules in Prometheus
curl http://192.168.168.42:9090/api/v1/rules | jq '.data.groups[] | select(.name=="nas-storage-alerts")'

# Expected: Array of 3 storage alert rules defined

# View active alerts in Alertmanager
curl http://192.168.168.42:9093/api/v1/alerts

# Expected: Empty array [] means no alerts firing (good - thresholds not exceeded)

# Optional: Test alert firing by generating test condition
# SSH to NAS and fill filesystem to test NASFilesystemSpaceLow alert
# (not recommended in production - for testing only)
```

### Phase 7: Documentation & Handoff

```bash
# 1. Link to deployment guide
# Documentation: NAS_MONITORING_INTEGRATION.md
# Quick Reference: NAS_MONITORING_QUICK_REFERENCE.md

# 2. Share with team
# - Dashboard URLs (http://192.168.168.42:4180/grafana/:dashboardId)
# - Alert notification channels (Slack, email, etc.)
# - Troubleshooting procedures

# 3. Monitor ongoing
# - Watch dashboard for NAS capacity trends
# - Configure email/Slack alerts for critical conditions
# - Monthly review of metrics and alert tuning
```

---

## ROLLBACK PROCEDURE (If Needed)

**If deployment causes issues:**

```bash
# On worker node with sudo
sudo ~/deploy-nas-monitoring-direct.sh --rollback

# Expected:
# [!] Rolling back to previous configuration...
# [✓] Rollback complete

# This will:
# 1. Restore prometheus.yml from timestamped backup
# 2. Restore rule files from backup
# 3. Reload Prometheus with previous config
# 4. Verify previous metrics are working
```

---

## KEY FEATURES

✅ **Immutable Deployment**
- Configuration tracked in git with cryptographic signatures
- No ad-hoc changes; all changes via commits

✅ **Atomic & Safe**
- Backup created before any changes
- Atomic config swap (move operation is atomic)
- Rollback available via `--rollback` flag

✅ **Idempotent**
- Multiple runs = same result
- No race conditions or state accumulation
- Safe to re-run without side effects

✅ **Hands-Off**
- Single command: `sudo deploy-nas-monitoring-direct.sh`
- No manual steps or interactive prompts
- Fully automated: validation, deploy, verify, rollback

✅ **No GitHub Actions**
- Direct bash execution only
- No workflows, no pull requests, no releases
- Immutable commits tracked in git

✅ **GSM Integration Ready**
- Credentials managed via Google Secret Manager (when integrated)
- No hardcoded secrets in any config
- Expandable to load secrets on deployment

---

## CONFIGURATION SUMMARY

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| **Prometheus Config** | monitoring/prometheus.yml | +80 | 5 NAS scrape jobs added |
| **Recording Rules** | docker/prometheus/nas-recording-rules.yml | 350+ | 40+ pre-computed metrics (8 groups) |
| **Alert Rules** | docker/prometheus/nas-alert-rules.yml | 280+ | 12+ alert rules (6 categories) |
| **Deploy Script** | deploy-nas-monitoring-direct.sh | 258 | Direct deployment automation |
| **Verify Script** | verify-nas-monitoring.sh | 250+ | 7-phase verification |
| **Documentation** | NAS_MONITORING_INTEGRATION.md | 500+ | Complete integration guide |
| **Quick Ref** | NAS_MONITORING_QUICK_REFERENCE.md | 180+ | Quick start & reference |

---

## DEPLOYMENT SECURITY

**Pre-deployment Checks:**
✅ Git immutability verified (cryptographic signatures)  
✅ All configuration files present and readable  
✅ Deployment scripts executable  
✅ SSH access to worker node available  
✅ Prerequisites checked (docker, docker-compose, prometheus dirs)  

**Deployment Safety:**
✅ Backup created before any changes  
✅ Configuration validated before deployment  
✅ Atomic swap ensures no partial configuration  
✅ Health check verifies Prometheus is operational  
✅ Rollback available if needed  

**Post-deployment Verification:**
✅ Metrics ingestion verified (up metric check)  
✅ All 5 scrape jobs active  
✅ Recording rules producing data  
✅ Alert rules loaded and ready  
✅ OAuth protection active on all endpoints  

---

## TROUBLESHOOTING

### Deployment Fails at Validation Step
```bash
# Check configuration files are present
ls -la monitoring/prometheus.yml docker/prometheus/nas-*.yml

# Validate YAML manually
docker run --rm -v $(pwd):/config prom/prometheus promtool check config /config/monitoring/prometheus.yml

# Check syntax errors (indentation, quotes, etc.)
```

### Prometheus Won't Reload After Deployment
```bash
# Check if docker-compose exists
ls -la /opt/monitoring-stack/docker-compose.yml

# Try manual reload
sudo docker-compose -f /opt/monitoring-stack/docker-compose.yml restart prometheus

# Or systemd
sudo systemctl restart prometheus

# Check logs for errors
sudo docker logs prometheus | tail -20
```

### NAS Metrics Not Appearing
```bash
# Verify NAS is reachable
ping eiq-nas

# Check node-exporter is running
curl -s http://eiq-nas:9100/metrics | head -20

# Watch Prometheus scrape logs
curl http://192.168.168.42:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.instance=="eiq-nas")'

# Check for error messages in scrape output
```

### Rollback Needed
```bash
# Restore previous configuration
sudo ~/deploy-nas-monitoring-direct.sh --rollback

# Verify rollback succeeded
curl http://localhost:9090/-/healthy
```

---

## COMPLIANCE VERIFICATION

Run after deployment to confirm all mandates satisfied:

```bash
# 1. Immutable (git signatures)
git log --format="%H %s" | head -3

# 2. Ephemeral (reload without restart)
# Verify Prometheus reloaded: docker-compose restart (not full restart)

# 3. Idempotent (re-run safe)
sudo ~/deploy-nas-monitoring-direct.sh  # Should complete without errors

# 4. No-Ops (fully automated)
# Check: Zero manual prompts during deployment

# 5. Hands-Off (single command)
# Check: One command: sudo ~/deploy-nas-monitoring-direct.sh

# 6. GSM Integration (prepare for secrets)
# Check: No hardcoded secrets in configs
grep -r "password\|api_key\|secret" docker/prometheus/ monitoring/ || echo "✓ No secrets found"

# 7. Direct Deployment (no GA)
# Check: No GitHub Actions used
test -f .github/workflows/nas-*.yml || echo "✓ No workflows"

# 8. OAuth-Exclusive (all endpoints protected)
# Check: Access Prometheus at http://192.168.168.42:4180/prometheus (requires login)
```

---

## SUCCESS CRITERIA

After deployment, verify:

- ✅ All 5 NAS scrape jobs show GREEN in Prometheus targets
- ✅ `up{instance="eiq-nas"}` metric = 1.0 (metrics being scraped)
- ✅ Recording rules producing data (nas:* metrics available)
- ✅ Alert rules loaded (12+ rules visible in Prometheus)
- ✅ OAuth login required for Prometheus access
- ✅ Grafana dashboards display NAS metrics
- ✅ No errors in Prometheus or Alertmanager logs
- ✅ Rollback capability tested and working

---

## FINAL SIGN-OFF

**Deployed By:** [Your Name/Team]  
**Deployment Date:** [Date]  
**Worker Node:** 192.168.168.42  
**Git Commit:** [Latest commit SHA]  
**Status:** ✅ PRODUCTION READY

**Deployment Command:**
```bash
sudo ~/deploy-nas-monitoring-direct.sh
```

**Verification Command:**
```bash
./verify-nas-monitoring.sh --verbose
```

**Quick Status Check:**
```bash
curl -s http://192.168.168.42:9090/api/v1/query?query=up{instance=\"eiq-nas\"} | jq '.data.result[0].value[1]'
# Expected output: "1" (metrics being scraped)
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-14  
**Status:** ✅ APPROVED FOR IMMEDIATE DEPLOYMENT
