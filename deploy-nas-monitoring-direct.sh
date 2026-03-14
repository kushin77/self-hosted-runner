#!/bin/bash
# NAS Host Monitoring - Direct Deployment (Worker Node 192.168.168.42)
# IMMUTABLE | EPHEMERAL | IDEMPOTENT | NO-OPS | HANDS-OFF | GSM-INTEGRATED | DIRECT DEPLOYMENT
# No GitHub Actions • No pull requests • Cryptographically signed git commits
#
# Usage: Run on worker node (192.168.168.42) after git pull
# ./deploy-nas-monitoring-direct.sh [--verify] [--rollback]
#
# Prerequisites: 
#   - Worker node at 192.168.168.42
#   - Root or sudo access
#   - Docker and docker-compose installed
#   - Prometheus running in docker-compose at /opt/monitoring-stack
#   - eiq-nas accessible on network with node-exporter on port 9100

set -e

# Configuration
WORKER_IP="192.168.168.42"
PROMETHEUS_CONF_DIR="/etc/prometheus"
PROMETHEUS_RULES_DIR="/etc/prometheus/rules"
BACKUP_DIR="$PROMETHEUS_CONF_DIR/.backups"
DEPLOYMENT_LOG="/tmp/nas-monitoring-deployment.log"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%SZ)
REPO_DIR="${REPO_DIR:-.}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# CLI Flags
VERIFY_ONLY=${1:-}
ROLLBACK=${2:-}

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }

# Initial checks
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  [[ $EUID -eq 0 ]] || { log_error "Must run as root"; exit 1; }
  [[ -d "$PROMETHEUS_CONF_DIR" ]] || { log_error "Prometheus config dir not found: $PROMETHEUS_CONF_DIR"; exit 1; }
  [[ -d "$PROMETHEUS_RULES_DIR" ]] || mkdir -p "$PROMETHEUS_RULES_DIR"
  
  which docker > /dev/null || { log_error "Docker not installed"; exit 1; }
  which docker-compose > /dev/null || { log_error "docker-compose not installed"; exit 1; }
  
  log_success "Prerequisites verified"
}

# Backup existing configuration
backup_config() {
  log_info "Creating configuration backup..."
  mkdir -p "$BACKUP_DIR"
  
  [[ -f "$PROMETHEUS_CONF_DIR/prometheus.yml" ]] && \
    cp "$PROMETHEUS_CONF_DIR/prometheus.yml" "$BACKUP_DIR/prometheus.yml.$TIMESTAMP"
  
  [[ -d "$PROMETHEUS_RULES_DIR" ]] && \
    cp -r "$PROMETHEUS_RULES_DIR" "$BACKUP_DIR/rules.$TIMESTAMP" 2>/dev/null || true
  
  log_success "Backup created: $BACKUP_DIR/prometheus.yml.$TIMESTAMP"
}

# Validate configuration files
validate_config() {
  log_info "Validating configuration files..."
  
  local config_files=(
    "$REPO_DIR/monitoring/prometheus.yml"
    "$REPO_DIR/docker/prometheus/nas-recording-rules.yml"
    "$REPO_DIR/docker/prometheus/nas-alert-rules.yml"
  )
  
  for file in "${config_files[@]}"; do
    [[ -f "$file" ]] || { log_error "Config file not found: $file"; return 1; }
  done
  
  # Validate YAML syntax
  log_info "Validating Prometheus YAML..."
  docker run --rm -v "$REPO_DIR/monitoring:/etc/prometheus" \
    prom/prometheus:latest \
    promtool check config /etc/prometheus/prometheus.yml > /tmp/prom-check.log 2>&1
  
  if grep -q "SUCCESS" /tmp/prom-check.log; then
    log_success "Prometheus config validated"
  else
    log_error "Prometheus config invalid"
    cat /tmp/prom-check.log
    return 1
  fi
  
  # Validate alert rules
  log_info "Validating alert rules..."
  docker run --rm -v "$REPO_DIR/docker/prometheus:/etc/prometheus" \
    prom/prometheus:latest \
    promtool check rules /etc/prometheus/nas-alert-rules.yml > /tmp/alerts-check.log 2>&1
  
  log_success "Alert rules validated"
  
  # Validate recording rules
  log_info "Validating recording rules..."
  docker run --rm -v "$REPO_DIR/docker/prometheus:/etc/prometheus" \
    prom/prometheus:latest \
    promtool check rules /etc/prometheus/nas-recording-rules.yml > /tmp/recording-check.log 2>&1
  
  log_success "Recording rules validated"
}

# Deploy configuration (atomic swap)
deploy_config() {
  log_info "Deploying configuration (atomic swap)..."
  
  # Copy new config with .new extension (atomic swap technique)
  cp "$REPO_DIR/monitoring/prometheus.yml" "$PROMETHEUS_CONF_DIR/prometheus.yml.new"
  
  # Copy rule files directly (idempotent)
  cp "$REPO_DIR/docker/prometheus/nas-recording-rules.yml" "$PROMETHEUS_RULES_DIR/"
  cp "$REPO_DIR/docker/prometheus/nas-alert-rules.yml" "$PROMETHEUS_RULES_DIR/"
  
  # Atomic rename
  mv -f "$PROMETHEUS_CONF_DIR/prometheus.yml.new" "$PROMETHEUS_CONF_DIR/prometheus.yml"
  
  log_success "Configuration deployed"
}

# Reload Prometheus
reload_prometheus() {
  log_info "Reloading Prometheus..."
  
  # Determine if docker-compose or systemd
  if [[ -f "/opt/monitoring-stack/docker-compose.yml" ]]; then
    log_info "Using docker-compose to reload Prometheus"
    cd /opt/monitoring-stack
    docker-compose restart prometheus > /tmp/compose-restart.log 2>&1
    cd - > /dev/null
  elif systemctl is-active --quiet prometheus; then
    log_info "Reloading Prometheus systemd service"
    systemctl reload prometheus
  else
    log_error "Could not find Prometheus (docker-compose or systemd)"
    return 1
  fi
  
  # Wait for health check
  log_info "Waiting for Prometheus to become healthy..."
  for i in {1..30}; do
    if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
      log_success "Prometheus healthy"
      return 0
    fi
    sleep 1
  done
  
  log_error "Prometheus did not become healthy after 30 seconds"
  return 1
}

# Verify metrics ingestion
verify_metrics() {
  log_info "Verifying metrics ingestion (waiting 30s for first scrape cycle)..."
  sleep 30
  
  # Check UP metric
  local up_metric=$(curl -s "http://localhost:9090/api/v1/query?query=up{instance=\"eiq-nas\"}" | jq '.data.result[0].value[1]' 2>/dev/null || echo "null")
  
  if [[ "$up_metric" == "1" ]]; then
    log_success "NAS metrics being scraped (up=1.0)"
    return 0
  elif [[ "$up_metric" == "0" ]]; then
    log_warning "NAS host DOWN (check network connectivity)"
    return 1
  else
    log_warning "Metrics not yet available (expected on first deployment, will be available soon)"
    return 0
  fi
}

# Rollback to previous configuration
rollback_config() {
  log_warning "Rolling back to previous configuration..."
  
  local latest_backup=$(ls -t "$BACKUP_DIR/prometheus.yml."* 2>/dev/null | head -1)
  [[ -z "$latest_backup" ]] && { log_error "No backups found"; return 1; }
  
  cp "$latest_backup" "$PROMETHEUS_CONF_DIR/prometheus.yml"
  
  # Also rollback rules if backup exists
  [[ -d "$BACKUP_DIR/rules."* ]] && \
    cp -r "$BACKUP_DIR"/rules.*/* "$PROMETHEUS_RULES_DIR/" 2>/dev/null || true
  
  reload_prometheus
  log_success "Rollback complete"
}

# Main deployment flow
main() {
  echo ""
  echo "========================================="
  echo "NAS Monitoring Direct Deployment"
  echo "Worker: $WORKER_IP"
  echo "Timestamp: $TIMESTAMP"
  echo "========================================="
  echo ""
  
  > "$DEPLOYMENT_LOG"  # Clear log
  
  if [[ "$ROLLBACK" == "--rollback" ]]; then
    rollback_config
    exit $?
  fi
  
  if [[ "$VERIFY_ONLY" != "--verify" ]]; then
    check_prerequisites || exit 1
    backup_config
    validate_config || exit 1
    deploy_config
    reload_prometheus || { rollback_config; exit 1; }
  fi
  
  verify_metrics
  local verify_status=$?
  
  echo ""
  echo "========================================="
  echo "✓ DEPLOYMENT COMPLETE"
  echo "========================================="
  echo ""
  echo "Configuration:"
  echo "  - Prometheus config: $PROMETHEUS_CONF_DIR/prometheus.yml"
  echo "  - Recording rules: $PROMETHEUS_RULES_DIR/nas-recording-rules.yml"
  echo "  - Alert rules: $PROMETHEUS_RULES_DIR/nas-alert-rules.yml"
  echo ""
  echo "Verification:"
  [[ $verify_status -eq 0 ]] && echo "  ✓ Metrics ingestion verified" || echo "  ⏳ Metrics pending (watch Prometheus targets)"
  echo ""
  echo "Next Steps:"
  echo "  1. Access Prometheus: http://192.168.168.42:4180/prometheus (OAuth login required)"
  echo "  2. Check Targets: Status → Targets → filter 'eiq-nas'"
  echo "  3. Verify All 5 Jobs: eiq-nas-{node,storage,network,process}-metrics (should be GREEN)"
  echo "  4. Create Grafana Dashboards: Use 'nas:*' recording rules"
  echo ""
  echo "Rollback (if needed):"
  echo "  ./deploy-nas-monitoring-direct.sh --rollback"
  echo ""
  echo "Deployment log: $DEPLOYMENT_LOG"
  echo ""
}

# Run main
main
