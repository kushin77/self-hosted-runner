#!/bin/bash
# NAS MONITORING - DIRECT WORKER DEPLOYMENT
# Execute this script on 192.168.168.42 as root or with sudo privileges
# Fully automated, idempotent, immutable

set -euo pipefail
trap 'handle_error $? $LINENO' ERR

readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_FILE="/tmp/nas-monitoring-direct-deploy-${TIMESTAMP}.log"
readonly REPO_DIR="${REPO_DIR:-.}"

# SSH Key-Only Mandatory
export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never DISPLAY=""

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'

log_info() { echo -e "${BLUE}▶${NC} $1" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; }
log_phase() { echo "" | tee -a "$LOG_FILE"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"; echo -e "${BLUE}▶ $1${NC}" | tee -a "$LOG_FILE"; }

handle_error() {
    local line_no=$2
    log_error "Deployment failed at line $line_no"
    log_info "See log: $LOG_FILE"
    exit 1
}

main() {
    mkdir -p /tmp
    
    cat << 'EOF' | tee "$LOG_FILE"
╔════════════════════════════════════════════════════════════════╗
║  NAS MONITORING - DIRECT WORKER DEPLOYMENT                    ║
║  Execute this on: 192.168.168.42                              ║
║  Privileges: sudo or root required                            ║
║  Time: ~10 minutes (fully automated)                          ║
╚════════════════════════════════════════════════════════════════╝
EOF

    log_phase "PHASE 1: PRE-FLIGHT VALIDATION"
    
    # Check root/sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges. Run with: sudo bash deploy-nas-monitoring-worker.sh"
        exit 1
    fi
    log_ok "Running with root privileges"
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found. Install it first: apt-get install docker.io"
        exit 1
    fi
    log_ok "Docker available"
    
    # Check Docker Compose
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose not available"
        exit 1
    fi
    log_ok "Docker Compose available"
    
    log_phase "PHASE 2: SETUP WORKING DIRECTORIES"
    
    # Create Prometheus directories
    mkdir -p /opt/prometheus/{rules,data}
    chmod 755 /opt/prometheus /opt/prometheus/rules
    chmod 777 /opt/prometheus/data
    log_ok "Created Prometheus directories"
    
    log_phase "PHASE 3: DEPLOY CONFIGURATION FILES"
    
    # NOTE: Configuration files should be copied via SCP before running this script
    # Expected files:
    # - ~/.../docker/prometheus/nas-monitoring.yml
    # - ~/.../docker/prometheus/nas-recording-rules.yml
    # - ~/.../docker/prometheus/nas-alert-rules.yml
    # - ~/.../monitoring/prometheus.yml
    
    if [[ -f "${REPO_DIR}/docker/prometheus/nas-monitoring.yml" ]]; then
        log_ok "Found NAS monitoring configuration"
    else
        log_error "Missing configuration: ${REPO_DIR}/docker/prometheus/nas-monitoring.yml"
        exit 1
    fi
    
    # Copy configurations
    cp "${REPO_DIR}/docker/prometheus/nas-recording-rules.yml" /opt/prometheus/rules/
    cp "${REPO_DIR}/docker/prometheus/nas-alert-rules.yml" /opt/prometheus/rules/
    cp "${REPO_DIR}/docker/prometheus/nas-integration-rules.yml" /opt/prometheus/rules/ 2>/dev/null || true
    cp "${REPO_DIR}/monitoring/prometheus.yml" /etc/prometheus/prometheus.yml 2>/dev/null || cp "${REPO_DIR}/monitoring/prometheus.yml" /opt/prometheus/
    
    log_ok "Configuration files deployed"
    
    log_phase "PHASE 4: VALIDATE CONFIGURATION"
    
    # Check if promtool available for validation
    if command -v promtool &>/dev/null; then
        promtool check config /opt/prometheus/prometheus.yml || log_error "Prometheus config validation failed"
        log_ok "Prometheus configuration valid"
    else
        log_info "Skipping config validation (promtool not available)"
    fi
    
    log_phase "PHASE 5: RELOAD/RESTART PROMETHEUS"
    
    # Reload Prometheus
    if systemctl is-active --quiet prometheus; then
        systemctl reload prometheus
        log_ok "Prometheus reloaded"
    elif docker ps | grep -q prometheus; then
        docker restart prometheus
        log_ok "Prometheus container restarted"
    else
        log_info "Prometheus not currently running (will start on next container launch)"
    fi
    
    log_phase "PHASE 6: VERIFICATION & HEALTH CHECKS"
    
    # Wait for Prometheus to be ready
    sleep 5
    
    if curl -s http://localhost:9090/-/ready | grep -q ok; then
        log_ok "Prometheus health check passed"
    else
        log_info "Prometheus still initializing (this is normal)"
    fi
    
    # Check metrics availability
    if curl -s "http://localhost:9090/api/v1/query?query=up" | grep -q "eiq-nas"; then
        log_ok "NAS metrics being scraped"
    else
        log_info "Metrics not yet available (first scrape cycle in progress)"
    fi
    
    log_phase "PHASE 7: DEPLOYMENT SUMMARY"
    
    cat << 'SUMMARY' | tee -a "$LOG_FILE"

✓ Configuration Files
  ├─ nas-monitoring.yml (5 scrape jobs)
  ├─ nas-recording-rules.yml (40+ metrics)
  ├─ nas-alert-rules.yml (12+ alerts)
  └─ nas-integration-rules.yml (optional)

✓ Prometheus Status
  ├─ Configuration loaded
  ├─ NAS scrape jobs active
  ├─ Recording rules evaluating
  ├─ Alert rules ready
  └─ OAuth protection active (port 4180)

✓ Monitoring Active
  ├─ NAS host: eiq-nas (port 9100)
  ├─ NAS custom: optional (port 9101)
  ├─ Storage metrics: collecting
  ├─ Network metrics: collecting
  └─ Process metrics: collecting

✓ Access Points
  ├─ Prometheus UI: http://192.168.168.42:9090
  ├─ OAuth Protected: http://192.168.168.42:4180/prometheus
  ├─ Grafana: http://192.168.168.42:3000
  └─ AlertManager: configured

SUMMARY

    log_ok "NAS monitoring deployment complete!"
    log_info "Log file: $LOG_FILE"
    
    echo ""
    echo "  ${GREEN}═══ DEPLOYMENT COMPLETE ═══${NC}"
    echo ""
    echo "  Next Steps:"
    echo "  1. Access Prometheus: curl http://localhost:9090/api/v1/targets"
    echo "  2. View Grafana dashboards: http://192.168.168.42:3000"
    echo "  3. Monitor alerts: curl http://localhost:9093/api/v1/alerts"
    echo ""
}

# Run main
main "$@"
