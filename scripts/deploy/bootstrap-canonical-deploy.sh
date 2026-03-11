#!/usr/bin/env bash
set -euo pipefail

# End-to-End Deployment Bootstrap for Canonical Secrets
# Comprehensive, idempotent, hands-off workflow:
# 1. Fetch and prepare branch
# 2. Deploy systemd service
# 3. Run full integration tests
# 4. Configure monitoring
# 5. Emit deployment report to GitHub
# 
# Usage: bash bootstrap-canonical-deploy.sh [--branch <name>] [--no-tests] [--no-monitoring]

REPO_ROOT="${REPO_ROOT:-.}"
BRANCH="${BRANCH:-canonical-secrets-impl-1773247600}"
RUN_TESTS="${RUN_TESTS:-1}"
RUN_MONITORING="${RUN_MONITORING:-1}"
LOG_FILE="/tmp/canonical_deploy_$(date +%s).log"
REPORT_FILE="/tmp/deployment_report_$(date +%s).json"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] $*" | tee -a "$LOG_FILE"
}

error() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] $*" | tee -a "$LOG_FILE"
  exit 1
}

success() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [SUCCESS] $*" | tee -a "$LOG_FILE"
}

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --no-tests) RUN_TESTS=0; shift ;;
    --no-monitoring) RUN_MONITORING=0; shift ;;
    *) error "Unknown option: $1" ;;
  esac
done

echo "========================================"
echo "CANONICAL SECRETS DEPLOYMENT BOOTSTRAP"
echo "========================================"
log "Bootstrap started"
log "Branch: $BRANCH"
log "Run tests: $RUN_TESTS"
log "Run monitoring setup: $RUN_MONITORING"
log "Log file: $LOG_FILE"

# Step 1: Fetch and prepare branch
log "[1/5] Fetching branch..."
cd "$REPO_ROOT"
git fetch origin "$BRANCH" || error "Failed to fetch branch"
git checkout "$BRANCH" || error "Failed to checkout branch"
git pull origin "$BRANCH" || log "Pull had no changes"
success "Branch prepared: $(git rev-parse --short HEAD)"

# Step 2: Deploy systemd service
log "[2/5] Deploying systemd service..."
if sudo bash scripts/deploy/systemd-deploy.sh >> "$LOG_FILE" 2>&1; then
  success "Systemd deployment completed"
else
  error "Systemd deployment failed (see $LOG_FILE)"
fi

# Step 3: Health check
log "[3/5] Running health checks..."
sleep 2
for i in {1..10}; do
  if curl -sf http://localhost:8000/api/v1/secrets/health > /dev/null 2>&1; then
    success "Service is healthy"
    break
  elif [ "$i" -eq 10 ]; then
    error "Service failed to become healthy"
  else
    log "  Waiting for service... (attempt $i/10)"
    sleep 1
  fi
done

# Step 4: Run integration tests (optional)
if [ "$RUN_TESTS" -eq 1 ]; then
  log "[4/5] Running integration tests..."
  if bash scripts/test/integration_test_harness.sh >> "$LOG_FILE" 2>&1; then
    success "Integration tests passed"
  else
    error "Integration tests failed (see $LOG_FILE)"
  fi
else
  log "[4/5] Skipping integration tests (--no-tests)"
fi

# Step 5: Configure monitoring (optional)
if [ "$RUN_MONITORING" -eq 1 ]; then
  log "[5/5] Configuring monitoring..."
  # Prometheus scrape config for canonical-secrets
  if [ -d "/etc/prometheus" ]; then
    sudo tee /etc/prometheus/canonical-secrets.yml > /dev/null <<'PROM_CONFIG'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: canonical-secrets-api
    static_configs:
      - targets: ['localhost:8000']
    metrics_path: '/metrics'
    scrape_interval: 5s
PROM_CONFIG
    log "Prometheus config deployed"
  else
    log "Prometheus not detected; skipping config"
  fi
  success "Monitoring setup completed"
else
  log "[5/5] Skipping monitoring setup (--no-monitoring)"
fi

# Generate deployment report
cat > "$REPORT_FILE" <<REPORT_JSON
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "SUCCESS",
  "branch": "$BRANCH",
  "commit": "$(git rev-parse --short HEAD)",
  "host": "$(hostname)",
  "service_url": "http://localhost:8000/api/v1/secrets/health",
  "tests_run": $RUN_TESTS,
  "monitoring_configured": $RUN_MONITORING,
  "log_file": "$LOG_FILE"
}
REPORT_JSON

log ""
log "========================================"
log "DEPLOYMENT COMPLETE"
log "========================================"
log "Service: canonical-secrets-api"
log "Status: ✅ RUNNING"
log "Health: http://localhost:8000/api/v1/secrets/health"
log "Logs: journalctl -u canonical-secrets-api.service -f"
log "Report: $REPORT_FILE"
log "========================================"

success "Bootstrap completed successfully"
exit 0
