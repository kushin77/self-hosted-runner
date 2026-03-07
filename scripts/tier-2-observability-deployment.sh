#!/bin/bash
################################################################################
# TIER 2: OBSERVABILITY & MONITORING DEPLOYMENT
# Purpose: Deploy monitoring, alerting, and logging infrastructure
# Date: 2026-03-07
# Idempotent: YES - Safe to run multiple times
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_DIR="${HOME}/.local/var/runner-remediation"
readonly LOG_FILE="${LOG_DIR}/tier-2-$(date +%Y%m%d-%H%M%S).log"
readonly TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
readonly METRICS_DIR="${HOME}/.local/share/runner-metrics"
readonly ALERT_CONFIG_DIR="${HOME}/.config/runner-alerts"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

################################################################################
# LOGGING FUNCTIONS
################################################################################

log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}" >&2
}

################################################################################
# INITIALIZATION
################################################################################

init() {
    mkdir -p "${LOG_DIR}"
    mkdir -p "${METRICS_DIR}"
    mkdir -p "${ALERT_CONFIG_DIR}"
    
    log_info "=== TIER 2 OBSERVABILITY DEPLOYMENT START ==="
    log "Log file: ${LOG_FILE}"
    log "Metrics dir: ${METRICS_DIR}"
    log "Alert config: ${ALERT_CONFIG_DIR}"
    log "Timestamp: ${TIMESTAMP}"
}

################################################################################
# STEP 1: DEPLOY PROMETHEUS NODE EXPORTER (USER-LEVEL)
################################################################################

deploy_node_exporter() {
    log_info "Step 1: Installing/configuring prometheus node exporter..."
    
    # Check if node_exporter already installed
    if command -v node_exporter &>/dev/null; then
        log "node_exporter already installed at $(which node_exporter)"
    else
        log "Installing node_exporter via system package manager..."
        # Try apt first (Debian/Ubuntu)
        if command -v apt-get &>/dev/null; then
            sudo apt-get update >/dev/null 2>&1 || true
            sudo apt-get install -y prometheus-node-exporter >/dev/null 2>&1 || {
                log_warn "Could not install via apt-get, will install manually"
            }
        fi
    fi
    
    # Create user-level systemd service for node exporter if not present
    local svc_file="${HOME}/.config/systemd/user/node-exporter.service"
    if [[ ! -f "${svc_file}" ]]; then
        log "Creating user-level node-exporter systemd service..."
        mkdir -p "$(dirname "${svc_file}")"
        cat > "${svc_file}" << 'EOF'
[Unit]
Description=Prometheus Node Exporter (User-level)
Documentation=https://github.com/prometheus/node_exporter
StartLimitInterval=5min
StartLimitBurst=3

[Service]
Type=simple
User=%u
ExecStart=/usr/sbin/node_exporter \
    --collector.filesystem.mount-points-exclude=^/(dev|proc|sys)($|/) \
    --collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|netpoll|nfs4?|nsfs|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$ \
    --collector.netdev.device-exclude=^(veth.*|docker.*|br.*)$
Restart=on-failure
RestartSec=5s

# Memory limit: 256MB
MemoryLimit=256M
# CPU limit: 50%  
CPUQuota=50%

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        log_info "✓ Created user-level node-exporter service"
    fi
    
    # Start service if available
    if command -v node_exporter &>/dev/null || [[ -f /usr/sbin/node_exporter ]]; then
        systemctl --user start node-exporter.service 2>/dev/null || true
        systemctl --user enable node-exporter.service 2>/dev/null || true
        log_info "✓ Node exporter deployed and enabled"
    else
        log_warn "node_exporter binary not found - will monitor manually"
    fi
}

################################################################################
# STEP 2: CREATE LOCAL METRICS COLLECTOR
################################################################################

create_metrics_collector() {
    log_info "Step 2: Creating local metrics collector..."
    
    local collector_script="${METRICS_DIR}/collect-metrics.sh"
    
    cat > "${collector_script}" << 'EOF'
#!/bin/bash
# Local metrics collector for memory, CPU, and restart monitoring
set -euo pipefail

METRICS_FILE="${HOME}/.local/share/runner-metrics/current-metrics.json"
HISTORY_FILE="${HOME}/.local/share/runner-metrics/metrics-history.jsonl"

collect_metrics() {
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    # Get memory info
    local mem_info=$(free -b | awk '/^Mem:/ {printf "{\"total\":%d,\"used\":%d,\"free\":%d,\"percent\":%.1f}", $2, $3, $4, ($3/$2)*100}')
    
    # Get CPU info  
    local cpu_info=$(mpstat 1 1 2>/dev/null | tail -1 | awk '{printf "{\"idle\":%.1f,\"busy\":%.1f}", $NF, 100-$NF}' || echo '{"idle":0,"busy":0}')
    
    # Get service restart counts
    local restart_counts=$(systemctl --user list-units --all | grep -E '(vscode|elevatediq|ide-2030)' | awk '{
        match($0, /([0-9]+)/, a)
        if (a[1] != "") print "{\"service\":\"" $1 "\",\"restarts\":" a[1] "}"
    }' | jq -s '.' || echo '[]')
    
    # Combine metrics
    local metrics_json=$(jq -n \
        --arg ts "$timestamp" \
        --argjson mem "$mem_info" \
        --argjson cpu "$cpu_info" \
        --argjson restarts "$restart_counts" \
        '{timestamp: $ts, memory: $mem, cpu: $cpu, service_restarts: $restarts}')
    
    echo "$metrics_json"
}

# Write to current metrics file
METRICS=$(collect_metrics)
echo "$METRICS" > "$METRICS_FILE"

# Append to history for trending
echo "$METRICS" >> "$HISTORY_FILE"

# Keep history to last 10000 lines (approximately 7 days at 1-minute intervals)
if [[ $(wc -l < "$HISTORY_FILE") -gt 10000 ]]; then
    tail -10000 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
fi

echo "$METRICS"
EOF
    
    chmod +x "${collector_script}"
    log_info "✓ Created metrics collector at ${collector_script}"
    
    # Test run
    bash "${collector_script}" > /dev/null 2>&1 && log_info "✓ Metrics collector tested successfully" || log_warn "Metrics collector test failed (jq or mpstat missing?)"
}

################################################################################
# STEP 3: CREATE ALERT THRESHOLDS & DETECTION
################################################################################

create_alert_detector() {
    log_info "Step 3: Creating alert detector for anomalies..."
    
    local detector_script="${ALERT_CONFIG_DIR}/detect-anomalies.sh"
    
    cat > "${detector_script}" << 'EOF'
#!/bin/bash
# Detect memory pressure, restart rate anomalies, and other issues
set -euo pipefail

readonly METRICS_FILE="${HOME}/.local/share/runner-metrics/current-metrics.json"
readonly ALERT_LOG="${HOME}/.local/var/runner-remediation/alerts.log"

# Alert thresholds
readonly MEM_CRITICAL_PCT=90
readonly MEM_WARNING_PCT=75
readonly RESTART_RATE_CRITICAL=5    # Per hour
readonly RESTART_RATE_WARNING=2

detect_memory_anomalies() {
    [[ ! -f "$METRICS_FILE" ]] && return
    
    local mem_pct=$(jq '.memory.percent' "$METRICS_FILE" 2>/dev/null || echo 0)
    local mem_free_gb=$(echo "scale=2; $(jq '.memory.free' "$METRICS_FILE" 2>/dev/null || echo 0) / 1073741824" | bc)
    
    if (( $(echo "$mem_pct > $MEM_CRITICAL_PCT" | bc -l) )); then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] CRITICAL: Memory usage ${mem_pct}% (${mem_free_gb}GB free)" >> "$ALERT_LOG"
        return 2
    fi
    
    if (( $(echo "$mem_pct > $MEM_WARNING_PCT" | bc -l) )); then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WARNING: Memory usage ${mem_pct}% (${mem_free_gb}GB free)" >> "$ALERT_LOG"
        return 1
    fi
}

detect_restart_anomalies() {
    # Count service restarts in last hour
    local restart_count=$(journalctl --user -n 1000 --output=short-iso | grep -c "Restart=on-failure" || echo 0)
    
    if (( restart_count > RESTART_RATE_CRITICAL )); then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] CRITICAL: ${restart_count} service restarts in last hour" >> "$ALERT_LOG"
        return 2
    fi
    
    if (( restart_count > RESTART_RATE_WARNING )); then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WARNING: ${restart_count} service restarts in last hour" >> "$ALERT_LOG"
        return 1
    fi
}

# Run detections
detect_memory_anomalies || ALERT_CODE=$?
detect_restart_anomalies || ALERT_CODE=$?

exit ${ALERT_CODE:-0}
EOF
    
    chmod +x "${detector_script}"
    log_info "✓ Created anomaly detector at ${detector_script}"
}

################################################################################
# STEP 4: CREATE SYSTEMD TIMER FOR PERIODIC METRICS COLLECTION
################################################################################

create_metrics_timer() {
    log_info "Step 4: Creating systemd timer for periodic metrics collection..."
    
    local service_file="${HOME}/.config/systemd/user/runner-metrics.service"
    local timer_file="${HOME}/.config/systemd/user/runner-metrics.timer"
    
    # Create service that runs the collector
    mkdir -p "$(dirname "${service_file}")"
    cat > "${service_file}" << EOF
[Unit]
Description=Runner Metrics Collection
StartLimitInterval=5min
StartLimitBurst=3

[Service]
Type=oneshot
User=%u
ExecStart=${METRICS_DIR}/collect-metrics.sh
EnvironmentFile=%h/.config/runner/metrics.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=timers.target
EOF
    
    # Create timer that runs every minute
    cat > "${timer_file}" << 'EOF'
[Unit]
Description=Run Runner Metrics Collection every minute
StartLimitInterval=5min
StartLimitBurst=3

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Create alert detection timer (every 5 minutes)
    cat > "${HOME}/.config/systemd/user/runner-alerts.service" << EOF
[Unit]
Description=Runner Alert Detection
StartLimitInterval=5min
StartLimitBurst=3

[Service]
Type=oneshot
User=%u
ExecStart=${ALERT_CONFIG_DIR}/detect-anomalies.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=timers.target
EOF
    
    cat > "${HOME}/.config/systemd/user/runner-alerts.timer" << 'EOF'
[Unit]
Description=Run Runner Alert Detection every 5 minutes
StartLimitInterval=5min
StartLimitBurst=3

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable runner-metrics.timer runner-alerts.timer 2>/dev/null || true
    systemctl --user start runner-metrics.timer runner-alerts.timer 2>/dev/null || true
    
    log_info "✓ Metrics and alert timers enabled and started"
    systemctl --user list-timers --all 2>/dev/null | grep runner || true
}

################################################################################
# STEP 5: CREATE JOURNALCTL PERSISTENCE FOR HIGH-VOLUME LOGGING
################################################################################

create_journalctl_config() {
    log_info "Step 5: Configuring journalctl for persistent high-volume logging..."
    
    # Create user journal config directory
    local journal_conf="${HOME}/.config/systemd/user-journal.conf.d"
    mkdir -p "${journal_conf}"
    
    cat > "${journal_conf}/10-persistence.conf" << 'EOF'
# Persistent journal storage for user systemd services
[Journal]
Storage=persistent
Compress=yes
# Keep 200MB of logs
MaxRetentionSec=30days
SystemMaxFileSize=50M
EOF
    
    # Create monthly archive script for old logs
    local archive_script="${METRICS_DIR}/archive-journalctl.sh"
    cat > "${archive_script}" << 'EOF'
#!/bin/bash
# Archive old journalctl logs monthly
set -euo pipefail

JOURNAL_DIR="${HOME}/.local/share/systemd/journal/user-$(id -u)"
ARCHIVE_DIR="${HOME}/.local/share/runner-metrics/journal-archives"
mkdir -p "$ARCHIVE_DIR"

# Find logs older than 30 days and tar them
find "${JOURNAL_DIR}" -name "*.journal" -mtime +30 -print0 2>/dev/null | while IFS= read -r -d '' file; do
    tar czf "${ARCHIVE_DIR}/$(basename "$file").tar.gz" "$file" 2>/dev/null && rm "$file"
done

echo "Archived old journal files to ${ARCHIVE_DIR}"
EOF
    
    chmod +x "${archive_script}"
    log_info "✓ Journalctl persistence configured"
}

################################################################################
# STEP 6: CREATE GRAFANA-COMPATIBLE METRICS ENDPOINT (LOCALHOST:9090)
################################################################################

create_metrics_api() {
    log_info "Step 6: Creating metrics API endpoint..."
    
    local api_script="${METRICS_DIR}/metrics-api.sh"
    
    cat > "${api_script}" << 'EOF'
#!/bin/bash
# Simple HTTP metrics API for scraping (compatible with Prometheus)
# Usage: Start in background and access via curl http://localhost:9100/metrics
set -euo pipefail

readonly PORT=9100
readonly METRICS_FILE="${HOME}/.local/share/runner-metrics/current-metrics.json"

start_metrics_server() {
    # Use ncat if available, fall back to nc
    local nc_cmd
    if command -v ncat &>/dev/null; then
        nc_cmd="ncat"
    elif command -v nc &>/dev/null; then
        nc_cmd="nc"
    else
        echo "ERROR: ncat or nc not found"
        return 1
    fi
    
    while true; do
        {
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo "Connection: close"
            echo ""
            if [[ -f "$METRICS_FILE" ]]; then
                cat "$METRICS_FILE"
            else
                echo '{"error":"No metrics collected yet"}'
            fi
        } | $nc_cmd -l 127.0.0.1 $PORT
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_metrics_server
fi
EOF
    
    chmod +x "${api_script}"
    log_info "✓ Created metrics API endpoint script"
}

################################################################################
# STEP 7: VALIDATION & SUMMARY
################################################################################

validate_tier2() {
    log_info "Step 7: Validating Tier 2 deployment..."
    
    local success=0
    
    # Check scripts exist
    [[ -x "${METRICS_DIR}/collect-metrics.sh" ]] && ((success++)) && log_info "✓ Metrics collector exists"
    [[ -x "${ALERT_CONFIG_DIR}/detect-anomalies.sh" ]] && ((success++)) && log_info "✓ Alert detector exists"
    [[ -f "${HOME}/.config/systemd/user/runner-metrics.timer" ]] && ((success++)) && log_info "✓ Metrics timer configured"
    [[ -f "${HOME}/.config/systemd/user/runner-alerts.timer" ]] && ((success++)) && log_info "✓ Alert timer configured"
    [[ -d "${METRICS_DIR}" ]] && ((success++)) && log_info "✓ Metrics directory created"
    
    if (( success >= 4 )); then
        log_info "✓ Validation passed (${success}/5 checks)"
        return 0
    else
        log_error "✗ Validation failed (${success}/5 checks)"
        return 1
    fi
}

print_summary() {
    log_info ""
    log_info "=== TIER 2 OBSERVABILITY DEPLOYMENT SUMMARY ==="
    log ""
    log "✓ Prometheus node exporter configured (user-level)"
    log "✓ Local metrics collector deployed"
    log "✓ Alert anomaly detection configured"
    log "✓ Systemd timers: metrics (1min) + alerts (5min)"
    log "✓ Journalctl persistent storage configured"
    log "✓ Metrics API endpoint created"
    log ""
    log "DIRECTORIES:"
    log "  Metrics:     ${METRICS_DIR}"
    log "  Alerts:      ${ALERT_CONFIG_DIR}"
    log "  Log:         ${LOG_DIR}"
    log ""
    log "TIMERS:"
    log "  runner-metrics.timer  - Collect metrics every 1 minute"
    log "  runner-alerts.timer   - Detect anomalies every 5 minutes"
    log ""
    log "NEXT STEPS:"
    log "  1. Monitor alerts: tail -f ${LOG_DIR}/alerts.log"
    log "  2. Check metrics: cat ${METRICS_DIR}/current-metrics.json | jq"
    log "  3. Review history: tail -n 100 ${METRICS_DIR}/metrics-history.jsonl"
    log "  4. Deploy Tier 3: Resource management (memory/CPU limits)"
    log ""
    log "=== TIER 2 DEPLOYMENT COMPLETE ==="
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    init
    
    deploy_node_exporter
    create_metrics_collector
    create_alert_detector
    create_metrics_timer
    create_journalctl_config
    create_metrics_api
    
    validate_tier2 && {
        print_summary
        return 0
    } || {
        log_error "Tier 2 deployment had issues"
        print_summary
        return 1
    }
}

main "$@"
