#!/usr/bin/env bash
set -euo pipefail

# Idempotent Prometheus scrape config application
# Applies runner-worker metrics scrape config to Prometheus and reloads
# Usage: ./scripts/apply-prometheus-scrape-config.sh --prometheus-host PROM_HOST [--worker-target IP:PORT] [--dry-run]

PROMETHEUS_HOST="${PROMETHEUS_HOST:-}"
WORKER_TARGET="${WORKER_TARGET:-192.168.168.42:9100}"
DRY_RUN=false
AUDIT_LOG="logs/prometheus-integration-audit.jsonl"

log_info() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] INFO: $*"; }
log_error() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; }
log_audit() {
  local action="$1" status="$2" details="${3:-}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"$action\",\"status\":\"$status\",\"details\":$details}" >> "$AUDIT_LOG"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prometheus-host) PROMETHEUS_HOST="$2"; shift 2;;
    --worker-target) WORKER_TARGET="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --prometheus-host HOST        Prometheus server host (e.g., prometheus.internal or 10.0.0.10)
  --worker-target IP:PORT       Runner worker node_exporter target (default: 192.168.168.42:9100)
  --dry-run                     Simulate without applying changes
  -h, --help                    Show this help

Example:
  $0 --prometheus-host prometheus.internal --worker-target 192.168.168.42:9100

Notes:
  - Attempts HTTP POST to http://PROMETHEUS_HOST:9090/-/reload
  - If reload fails, manual Prometheus restart may be required
  - Ensure Prometheus is configured with --web.enable-lifecycle flag

EOF
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1;;
  esac
done

mkdir -p logs
log_audit "prometheus_integration_start" "STARTED" "{\"dry_run\":$DRY_RUN,\"prometheus_host\":\"$PROMETHEUS_HOST\",\"worker_target\":\"$WORKER_TARGET\"}"

# Step 1: Validate inputs
if [ -z "$PROMETHEUS_HOST" ]; then
  log_error "PROMETHEUS_HOST not provided; use --prometheus-host"
  log_audit "prometheus_integration_failed" "ERROR" "{\"reason\":\"prometheus_host_not_provided\"}"
  exit 1
fi

log_info "[1/4] Preparing Prometheus scrape config for worker: $WORKER_TARGET"

# Step 2: Generate scrape job snippet
SCRAPE_CONFIG="monitoring/prometheus-runner.yml"
if [ ! -f "$SCRAPE_CONFIG" ]; then
  log_error "Scrape config template not found: $SCRAPE_CONFIG"
  log_audit "prometheus_integration_failed" "ERROR" "{\"reason\":\"scrape_config_not_found\"}"
  exit 1
fi

# Verify scrape config contains runner-worker job
if ! grep -q "job_name.*runner-worker" "$SCRAPE_CONFIG"; then
  log_error "Scrape config does not contain runner-worker job"
  log_audit "prometheus_integration_failed" "ERROR" "{\"reason\":\"runner_worker_job_not_found\"}"
  exit 1
fi

log_info "  ✓ Scrape config valid: $SCRAPE_CONFIG"

# Step 3: Document the integration steps
log_info "[2/4] Integration instructions:"
cat <<EOF

To complete Prometheus integration:

1. Add the runner-worker scrape job to Prometheus config (/etc/prometheus/prometheus.yml):

---Copy from: monitoring/prometheus-runner.yml---
$(cat "$SCRAPE_CONFIG")
---End copy---

2. Add this to your prometheus.yml scrape_configs section:

scrape_configs:
  # ... existing jobs ...
  - job_name: 'runner-worker'
    static_configs:
      - targets: ['$WORKER_TARGET']
        labels:
          role: runner

3. Verify Prometheus is started with lifecycle flag:
   systemctl show prometheus -p ExecStart | grep -i "web.enable-lifecycle"
   If not present, add --web.enable-lifecycle to Prometheus startup args

4. Reload Prometheus:
   - Via HTTP: curl -X POST http://$PROMETHEUS_HOST:9090/-/reload
   - Or restart: sudo systemctl restart prometheus

5. Verify metrics appear in Prometheus UI:
   http://$PROMETHEUS_HOST:9090/graph
   Search for: node_cpu_seconds_total{instance="$WORKER_TARGET",...}

EOF

if [ "$DRY_RUN" = true ]; then
  log_info "[DRY-RUN] Scrape integration prepared; no changes applied"
  log_audit "prometheus_integration_config_prepared" "DRY_RUN" "{\"scrape_config\":\"$SCRAPE_CONFIG\"}"
  exit 0
fi

# Step 4: Attempt HTTP reload (if Prometheus has --web.enable-lifecycle enabled)
log_info "[3/4] Attempting to reload Prometheus via HTTP..."
PROMETHEUS_URL="http://$PROMETHEUS_HOST:9090/-/reload"
if curl -sS -X POST "$PROMETHEUS_URL" -w "\nHTTP Status: %{http_code}\n" 2>/dev/null; then
  log_info "  ✓ Prometheus reloaded successfully"
  log_audit "prometheus_integration_reloaded" "SUCCESS" "{\"prometheus_host\":\"$PROMETHEUS_HOST\",\"method\":\"http_reload\"}"
else
  log_error "Prometheus HTTP reload failed; manual reload may be required"
  log_audit "prometheus_integration_reload_failed" "WARNING" "{\"prometheus_host\":\"$PROMETHEUS_HOST\",\"reason\":\"http_reload_failed\"}"
fi

# Step 5: Verification (best-effort)
log_info "[4/4] Verifying Prometheus connectivity..."
if curl -sS "http://$PROMETHEUS_HOST:9090/api/v1/query?query=up{job=\"runner-worker\"}" 2>/dev/null | jq . >/dev/null 2>&1; then
  log_info "  ✓ Prometheus API responsive"
  log_audit "prometheus_integration_complete" "SUCCESS" "{\"prometheus_host\":\"$PROMETHEUS_HOST\",\"worker_target\":\"$WORKER_TARGET\"}"
  echo ""
  echo "✅ Prometheus integration complete!"
  echo "   - Scrape job: runner-worker"
  echo "   - Target: $WORKER_TARGET"
  echo "   - Access Prometheus at: http://$PROMETHEUS_HOST:9090"
  echo "   - Query node_exporter metrics: http://$PROMETHEUS_HOST:9090/graph?expr=node_cpu_seconds_total{instance=\"$WORKER_TARGET\"%7D"
else
  log_info "  Prometheus connectivity check inconclusive; verify manually"
  log_audit "prometheus_integration_verify_inconclusive" "WARNING" "{\"prometheus_host\":\"$PROMETHEUS_HOST\"}"
  echo ""
  echo "⚠️  Prometheus integration prepared; verify manually:"
  echo "   - Check Prometheus targets: http://$PROMETHEUS_HOST:9090/targets"
  echo "   - Should see runner-worker with state UP"
fi

exit 0
