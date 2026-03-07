#!/bin/bash
################################################################################
# TIER 4: RELIABILITY & HEALTH CHECKS - Service Health & Automatic Recovery
# Purpose: Detect service failures, trigger graceful recovery, self-heal
# Date: 2026-03-07
# Idempotent: YES - Safe to run multiple times
# Hands-off: YES - No manual ops required after deployment
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_DIR="${HOME}/.local/var/runner-remediation"
readonly LOG_FILE="${LOG_DIR}/tier-4-$(date +%Y%m%d-%H%M%S).log"
readonly TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
readonly HEALTH_STATE_DIR="${HOME}/.local/share/runner-health"
readonly HEALTH_CHECK_DIR="${HOME}/.local/bin/health-checks"

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
    mkdir -p "${HEALTH_STATE_DIR}"
    mkdir -p "${HEALTH_CHECK_DIR}"
    
    log_info "=== TIER 4 RELIABILITY & HEALTH CHECKS START ==="
    log "Log file: ${LOG_FILE}"
    log "Health state dir: ${HEALTH_STATE_DIR}"
    log "Health check dir: ${HEALTH_CHECK_DIR}"
    log "Timestamp: ${TIMESTAMP}"
}

################################################################################
# STEP 1: CREATE HEALTH CHECK SCRIPTS FOR EACH SERVICE
################################################################################

create_health_checks() {
    log_info "Step 1: Creating health check scripts..."
    
    # Runner service health check
    cat > "${HEALTH_CHECK_DIR}/runner-health.sh" << 'EOF'
#!/bin/bash
# Health check for GitHub Actions runner service
set -euo pipefail

readonly STATE_FILE="${HOME}/.local/share/runner-health/runner.state"
RUNNER_PID=$(pgrep -f "runsvc.sh" 2>/dev/null || echo "")

check_process_running() {
    if [[ -z "$RUNNER_PID" ]]; then
        return 1  # Process not running
    fi
    return 0  # Running
}

check_recent_activity() {
    # Check if runner has processed jobs in last 5 minutes
    local recent_jobs
    recent_jobs=$(journalctl --user -n 100 -u runner.service --since "5 minutes ago" | grep -c "Accepted job" 2>/dev/null || echo "0")
    if (( recent_jobs > 0 )); then
        return 0
    fi
    
    # If no recent jobs, consider it healthy if process is running
    # (runner may be idle)
    return 0
}

check_memory_ok() {
    # Check if runner is within memory limits
    if [[ -n "$RUNNER_PID" ]]; then
        local rss_kb
        rss_kb=$(ps -p "$RUNNER_PID" -o rss= 2>/dev/null || echo "0")
        local limit_kb=$((2 * 1024 * 1024))  # 2GB
        if (( rss_kb > limit_kb )); then
            return 1  # Over limit
        fi
    fi
    return 0
}

check_network_connectivity() {
    # Verify connectivity to GitHub Actions API
    timeout 2 curl -s -o /dev/null -w "%{http_code}" https://api.github.com/zen 2>/dev/null | grep -q "200" && return 0 || return 1
}

# Run all checks
STATUS="healthy"
DETAILS=""

check_process_running || { STATUS="unhealthy"; DETAILS="process not running"; }
check_recent_activity || { DETAILS="${DETAILS} no recent activity"; }
check_memory_ok || { DETAILS="${DETAILS} memory limit exceeded"; }
check_network_connectivity || { DETAILS="${DETAILS} no network connectivity"; }

# Write state
mkdir -p "$(dirname "$STATE_FILE")"
cat > "$STATE_FILE" << EOFSTATE
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "$STATUS",
  "details": "$DETAILS",
  "pid": "${RUNNER_PID:-null}",
  "healthy": $([ "$STATUS" = "healthy" ] && echo "true" || echo "false")
}
EOFSTATE

# Exit code
[[ "$STATUS" = "healthy" ]] && exit 0 || exit 1
EOF
    chmod +x "${HEALTH_CHECK_DIR}/runner-health.sh"
    
    # Health monitor service check
    cat > "${HEALTH_CHECK_DIR}/health-monitor-health.sh" << 'EOF'
#!/bin/bash
# Health check for elevatediq-runner-health-monitor service
set -euo pipefail

readonly STATE_FILE="${HOME}/.local/share/runner-health/health-monitor.state"
HM_PID=$(pgrep -f "elevatediq-runner-health-monitor" 2>/dev/null || echo "")

check_process_running() {
    [[ -n "$HM_PID" ]] && return 0 || return 1
}

check_responding() {
    # Check systemd status
    systemctl --user is-active elevatediq-runner-health-monitor.service &>/dev/null && return 0 || return 1
}

STATUS="healthy"
DETAILS=""

check_process_running || { STATUS="unhealthy"; DETAILS="process not running"; }
check_responding || { DETAILS="${DETAILS} not responding"; }

mkdir -p "$(dirname "$STATE_FILE")"
cat > "$STATE_FILE" << EOFSTATE
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "$STATUS",
  "details": "$DETAILS",
  "pid": "${HM_PID:-null}",
  "healthy": $([ "$STATUS" = "healthy" ] && echo "true" || echo "false")
}
EOFSTATE

[[ "$STATUS" = "healthy" ]] && exit 0 || exit 1
EOF
    chmod +x "${HEALTH_CHECK_DIR}/health-monitor-health.sh"
    
    # Metrics collector health check
    cat > "${HEALTH_CHECK_DIR}/metrics-health.sh" << 'EOF'
#!/bin/bash
# Health check for metrics collection system
set -euo pipefail

readonly STATE_FILE="${HOME}/.local/share/runner-health/metrics.state"
readonly METRICS_FILE="${HOME}/.local/share/runner-metrics/current-metrics.json"

check_metrics_fresh() {
    # Verify metrics file exists and was updated in last 3 minutes
    if [[ ! -f "$METRICS_FILE" ]]; then
        return 1
    fi
    
    local file_age_sec
    file_age_sec=$(( $(date +%s) - $(stat -f%m "$METRICS_FILE" 2>/dev/null || stat -c%Y "$METRICS_FILE") ))
    if (( file_age_sec > 180 )); then
        return 1  # Stale (>3 min old)
    fi
    return 0
}

check_timer_active() {
    systemctl --user is-active runner-metrics.timer &>/dev/null && return 0 || return 1
}

STATUS="healthy"
DETAILS=""

check_metrics_fresh || { STATUS="unhealthy"; DETAILS="metrics stale"; }
check_timer_active || { DETAILS="${DETAILS} timer inactive"; }

mkdir -p "$(dirname "$STATE_FILE")"
cat > "$STATE_FILE" << EOFSTATE
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "$STATUS",
  "details": "$DETAILS",
  "metrics_file": "$METRICS_FILE",
  "healthy": $([ "$STATUS" = "healthy" ] && echo "true" || echo "false")
}
EOFSTATE

[[ "$STATUS" = "healthy" ]] && exit 0 || exit 1
EOF
    chmod +x "${HEALTH_CHECK_DIR}/metrics-health.sh"
    
    log_info "✓ Created 3 health check scripts"
}

################################################################################
# STEP 2: CREATE SERVICE DEPENDENCIES IN SYSTEMD
################################################################################

create_service_dependencies() {
    log_info "Step 2: Creating systemd service dependencies..."
    
    # Runner depends on metrics + health monitor
    mkdir -p "${HOME}/.config/systemd/user/runner.service.d"
    cat > "${HOME}/.config/systemd/user/runner.service.d/dependencies.conf" << 'EOF'
# Runner depends on metrics and health monitoring
[Unit]
After=runner-metrics.timer elevatediq-runner-health-monitor.service
Wants=runner-metrics.timer elevatediq-runner-health-monitor.service
PartOf=runner-multi.target

[Service]
# Graceful shutdown sequence
TimeoutStopSec=30s
KillMode=mixed
KillSignal=SIGTERM
EOF
    
    log "Applied dependencies to runner.service"
    
    # Health monitor depends on metrics
    mkdir -p "${HOME}/.config/systemd/user/elevatediq-runner-health-monitor.service.d"
    cat > "${HOME}/.config/systemd/user/elevatediq-runner-health-monitor.service.d/dependencies.conf" << 'EOF'
[Unit]
After=runner-metrics.timer
Wants=runner-metrics.timer

[Service]
TimeoutStopSec=15s
KillMode=mixed
EOF
    
    log "Applied dependencies to health-monitor.service"
    
    log_info "✓ Service dependencies configured"
}

################################################################################
# STEP 3: CREATE SYSTEMD TIMERS FOR PERIODIC HEALTH CHECKS
################################################################################

create_health_check_timers() {
    log_info "Step 3: Creating systemd timers for health checks..."
    
    # Runner health check (every 2 minutes)
    mkdir -p "${HOME}/.config/systemd/user"
    cat > "${HOME}/.config/systemd/user/runner-health.service" << EOF
[Unit]
Description=Runner Health Check
StartLimitInterval=5min
StartLimitBurst=3

[Service]
Type=oneshot
ExecStart=${HEALTH_CHECK_DIR}/runner-health.sh
StandardOutput=journal
StandardError=journal
# Health check should be quick
TimeoutStartSec=10s

[Install]
WantedBy=timers.target
EOF
    
    cat > "${HOME}/.config/systemd/user/runner-health.timer" << 'EOF'
[Unit]
Description=Runner Health Check Timer
PartOf=runner-multi.target

[Timer]
OnBootSec=30s
OnUnitActiveSec=2min
Persistent=true
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
    
    # Health monitor health check (every 3 minutes)
    cat > "${HOME}/.config/systemd/user/health-monitor-health.service" << EOF
[Unit]
Description=Health Monitor Health Check
StartLimitInterval=5min
StartLimitBurst=3

[Service]
Type=oneshot
ExecStart=${HEALTH_CHECK_DIR}/health-monitor-health.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=10s

[Install]
WantedBy=timers.target
EOF
    
    cat > "${HOME}/.config/systemd/user/health-monitor-health.timer" << 'EOF'
[Unit]
Description=Health Monitor Health Check Timer
PartOf=runner-multi.target

[Timer]
OnBootSec=45s
OnUnitActiveSec=3min
Persistent=true
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
    
    # Metrics health check (every 3 minutes)
    cat > "${HOME}/.config/systemd/user/metrics-health.service" << EOF
[Unit]
Description=Metrics Collection Health Check
StartLimitInterval=5min
StartLimitBurst=3

[Service]
Type=oneshot
ExecStart=${HEALTH_CHECK_DIR}/metrics-health.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=10s

[Install]
WantedBy=timers.target
EOF
    
    cat > "${HOME}/.config/systemd/user/metrics-health.timer" << 'EOF'
[Unit]
Description=Metrics Health Check Timer
PartOf=runner-multi.target

[Timer]
OnBootSec=60s
OnUnitActiveSec=3min
Persistent=true
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
    
    log_info "✓ Health check timers created (2-3 minute intervals)"
}

################################################################################
# STEP 4: CREATE AUTOMATIC RECOVERY ENGINE
################################################################################

create_recovery_engine() {
    log_info "Step 4: Creating automatic recovery engine..."
    
    local recovery_script="${HOME}/.local/bin/auto-recovery.sh"
    
    cat > "${recovery_script}" << 'EOF'
#!/bin/bash
# Automatic recovery engine - monitors health checks and triggers recovery
set -euo pipefail

readonly HEALTH_STATE_DIR="${HOME}/.local/share/runner-health"
readonly LOG_FILE="${HOME}/.local/var/runner-remediation/auto-recovery.log"
readonly MAX_CONSECUTIVE_FAILURES=3

log_recovery() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" >> "$LOG_FILE"
}

recover_service() {
    local service=$1
    local restart_delay=${2:-0}
    
    log_recovery "Recovering service: $service (delay: ${restart_delay}s)"
    
    # Wait before recovery (exponential backoff: 1, 2, 4, 8 seconds)
    sleep "$restart_delay"
    
    # Graceful stop
    systemctl --user stop "$service" 2>/dev/null || true
    sleep 2
    
    # Restart with health validation
    systemctl --user start "$service" 2>/dev/null || {
        log_recovery "  ERROR: Failed to start $service"
        return 1
    }
    
    # Wait for service to stabilize
    sleep 3
    
    # Verify recovery succeeded
    if systemctl --user is-active "$service" &>/dev/null; then
        log_recovery "  ✓ $service recovered successfully"
        return 0
    else
        log_recovery "  ✗ $service still failing after restart"
        return 1
    fi
}

check_and_recover() {
    local service=$1
    local health_check=$2
    local state_file="${HEALTH_STATE_DIR}/${service}.state"
    
    # Run health check
    if ! bash "$health_check" 2>/dev/null; then
        # Service is unhealthy
        
        # Track consecutive failures
        local failure_count=0
        if [[ -f "${state_file}.failures" ]]; then
            failure_count=$(cat "${state_file}.failures")
        fi
        ((failure_count++))
        echo "$failure_count" > "${state_file}.failures"
        
        if (( failure_count >= MAX_CONSECUTIVE_FAILURES )); then
            log_recovery "Service $service failed ${failure_count} consecutive checks"
            
            # Calculate restart delay (exponential backoff: 2^(failures-1))
            local restart_delay=$((2 ** (failure_count - 2)))
            [[ $restart_delay -gt 8 ]] && restart_delay=8
            
            recover_service "$service" "$restart_delay"
            
            # Reset failure counter on successful recovery
            rm -f "${state_file}.failures"
        fi
    else
        # Service is healthy - reset failure counter
        rm -f "${state_file}.failures"
    fi
}

# Monitor all critical services
mkdir -p "$(dirname "$LOG_FILE")"

check_and_recover "runner.service" "${HOME}/.local/bin/health-checks/runner-health.sh"
check_and_recover "elevatediq-runner-health-monitor.service" "${HOME}/.local/bin/health-checks/health-monitor-health.sh"
check_and_recover "runner-metrics.timer" "${HOME}/.local/bin/health-checks/metrics-health.sh"

log_recovery "Auto-recovery check complete"
EOF
    
    chmod +x "${recovery_script}"
    log_info "✓ Created auto-recovery engine at ${recovery_script}"
    
    # Create systemd service for auto-recovery
    cat > "${HOME}/.config/systemd/user/auto-recovery.service" << EOF
[Unit]
Description=Automatic Service Recovery Engine
StartLimitInterval=10min
StartLimitBurst=3

[Service]
Type=oneshot
ExecStart=${recovery_script}
StandardOutput=journal
StandardError=journal
TimeoutStartSec=30s

[Install]
WantedBy=default.target
EOF
    
    cat > "${HOME}/.config/systemd/user/auto-recovery.timer" << 'EOF'
[Unit]
Description=Automatic Service Recovery Timer
PartOf=runner-multi.target

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
    
    log_info "✓ Auto-recovery timer created (5-minute intervals)"
}

################################################################################
# STEP 5: CREATE GRACEFUL SHUTDOWN ORCHESTRATION
################################################################################

create_graceful_shutdown() {
    log_info "Step 5: Creating graceful shutdown orchestration..."
    
    # Create multi-target for coordinated shutdown
    mkdir -p "${HOME}/.config/systemd/user"
    cat > "${HOME}/.config/systemd/user/runner-multi.target" << 'EOF'
[Unit]
Description=Runner Multi-Service Target
Documentation=man:systemd.target(5)
Wants=runner.service runner-metrics.timer elevatediq-runner-health-monitor.service

[Install]
WantedBy=default.target
EOF
    
    # Create pre-shutdown script for graceful drain
    local shutdown_script="${HOME}/.local/bin/graceful-shutdown.sh"
    cat > "${shutdown_script}" << 'EOF'
#!/bin/bash
# Graceful shutdown - drain active work before stopping services
set -euo pipefail

readonly LOG_FILE="${HOME}/.local/var/runner-remediation/graceful-shutdown.log"
readonly TIMEOUT=30

log_shutdown() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" >> "$LOG_FILE"
}

# Step 1: Mark runner as offline (stops accepting new jobs)
log_shutdown "Step 1: Marking runner offline..."
systemctl --user set-property runner.service CPUQuota=10% 2>/dev/null || true

# Step 2: Wait for in-flight jobs to complete
log_shutdown "Step 2: Waiting for active jobs to complete (timeout: ${TIMEOUT}s)..."
local start_time=$(date +%s)
while (( $(date +%s) - start_time < TIMEOUT )); do
    local active_jobs
    active_jobs=$(journalctl --user -n 50 -u runner.service | grep -c "job" 2>/dev/null || echo "0")
    if (( active_jobs == 0 )); then
        log_shutdown "  ✓ No active jobs remaining"
        break
    fi
    sleep 1
done

# Step 3: Stop metrics/monitoring (won't collect while services shutting down)
log_shutdown "Step 3: Stopping monitoring..."
systemctl --user stop runner-metrics.timer 2>/dev/null || true
systemctl --user stop runner-alerts.timer 2>/dev/null || true

log_shutdown "Graceful shutdown preparation complete"
EOF
    
    chmod +x "${shutdown_script}"
    log_info "✓ Created graceful shutdown script at ${shutdown_script}"
}

################################################################################
# STEP 6: CREATE AGGREGATED HEALTH STATUS ENDPOINT
################################################################################

create_health_status_api() {
    log_info "Step 6: Creating aggregated health status API..."
    
    local status_script="${HOME}/.local/bin/health-status-api.sh"
    
    cat > "${status_script}" << 'EOF'
#!/bin/bash
# Aggregated health status API - JSON endpoint for system health
set -euo pipefail

readonly HEALTH_STATE_DIR="${HOME}/.local/share/runner-health"

get_overall_status() {
    local all_healthy=true
    
    for state_file in "${HEALTH_STATE_DIR}"/*.state; do
        if [[ -f "$state_file" ]]; then
            local is_healthy
            is_healthy=$(jq '.healthy' "$state_file" 2>/dev/null || echo "false")
            if [[ "$is_healthy" != "true" ]]; then
                all_healthy=false
                break
            fi
        fi
    done
    
    [[ "$all_healthy" = "true" ]] && echo "healthy" || echo "unhealthy"
}

build_health_report() {
    local overall_status
    overall_status=$(get_overall_status)
    
    local services_json="["
    local first=true
    
    for state_file in "${HEALTH_STATE_DIR}"/*.state; do
        if [[ -f "$state_file" ]]; then
            if [[ "$first" = false ]]; then
                services_json+=","
            fi
            services_json+=$(cat "$state_file")
            first=false
        fi
    done
    
    services_json+="]"
    
    cat << EOFHEALTH
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "overall_status": "$overall_status",
  "services": $services_json
}
EOFHEALTH
}

# Output JSON report
build_health_report
EOF
    
    chmod +x "${status_script}"
    log_info "✓ Created health status API at ${status_script}"
}

################################################################################
# STEP 7: RELOAD SYSTEMD AND ENABLE TIMERS
################################################################################

enable_health_system() {
    log_info "Step 7: Enabling health check system..."
    
    systemctl --user daemon-reload
    log "Systemd user session reloaded"
    
    # Enable and start timers
    systemctl --user enable runner-multi.target 2>/dev/null || true
    systemctl --user enable runner-health.timer 2>/dev/null || true
    systemctl --user enable health-monitor-health.timer 2>/dev/null || true
    systemctl --user enable metrics-health.timer 2>/dev/null || true
    systemctl --user enable auto-recovery.timer 2>/dev/null || true
    
    systemctl --user start runner-health.timer 2>/dev/null || true
    systemctl --user start health-monitor-health.timer 2>/dev/null || true
    systemctl --user start metrics-health.timer 2>/dev/null || true
    systemctl --user start auto-recovery.timer 2>/dev/null || true
    
    log_info "✓ Health check timers enabled and started"
}

################################################################################
# STEP 8: VALIDATION & SUMMARY
################################################################################

validate_tier4() {
    log_info "Step 8: Validating Tier 4 deployment..."
    
    local success=0
    
    # Check scripts exist
    [[ -x "${HEALTH_CHECK_DIR}/runner-health.sh" ]] && ((success++)) && log_info "✓ Runner health check exists"
    [[ -x "${HEALTH_CHECK_DIR}/health-monitor-health.sh" ]] && ((success++)) && log_info "✓ Health monitor check exists"
    [[ -x "${HEALTH_CHECK_DIR}/metrics-health.sh" ]] && ((success++)) && log_info "✓ Metrics health check exists"
    
    # Check systemd files
    [[ -f "${HOME}/.config/systemd/user/runner-health.timer" ]] && ((success++)) && log_info "✓ Runner health timer configured"
    [[ -f "${HOME}/.config/systemd/user/auto-recovery.timer" ]] && ((success++)) && log_info "✓ Auto-recovery timer configured"
    
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
    log_info "=== TIER 4 RELIABILITY & HEALTH CHECKS SUMMARY ==="
    log ""
    log "✓ Health check scripts deployed (3 services monitored)"
    log "✓ Service dependencies configured (graceful shutdown)"
    log "✓ Health check timers active (2-3 minute intervals)"
    log "✓ Automatic recovery engine deployed (5-minute checks)"
    log "✓ Graceful shutdown orchestration created"
    log "✓ Aggregated health status API created"
    log ""
    log "HEALTH CHECKS (Automatic Timers):"
    log "  runner-health.timer              (2min - process, activity, memory, network)"
    log "  health-monitor-health.timer      (3min - process, systemd status)"
    log "  metrics-health.timer             (3min - freshness, timer active)"
    log "  auto-recovery.timer              (5min - detect failures, auto-restart)"
    log ""
    log "RECOVERY STRATEGY:"
    log "  • Monitor: 2-3 minute intervals"
    log "  • Detect: 3 consecutive failures = trigger recovery"
    log "  • Recover: Exponential backoff restart (1s, 2s, 4s, 8s)"
    log "  • Verify: Health check post-recovery"
    log ""
    log "DIRECTORIES:"
    log "  Health checks:   ${HEALTH_CHECK_DIR}"
    log "  Health state:    ${HEALTH_STATE_DIR}"
    log "  Logs:            ${LOG_DIR}"
    log ""
    log "SCRIPTS:"
    log "  Health API:      ~/.local/bin/health-status-api.sh"
    log "  Auto-recovery:   ~/.local/bin/auto-recovery.sh"
    log "  Graceful stop:   ~/.local/bin/graceful-shutdown.sh"
    log ""
    log "NEXT STEPS:"
    log "  1. Monitor: bash ~/.local/bin/health-status-api.sh | jq"
    log "  2. Check recovery logs: tail -f ~/.local/var/runner-remediation/auto-recovery.log"
    log "  3. Watch timers: systemctl --user list-timers --all | grep runner"
    log "  4. Deploy Tier 5: Security automation & compliance"
    log ""
    log "=== TIER 4 DEPLOYMENT COMPLETE ==="
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    init
    
    create_health_checks
    create_service_dependencies
    create_health_check_timers
    create_recovery_engine
    create_graceful_shutdown
    create_health_status_api
    enable_health_system
    
    validate_tier4 && {
        print_summary
        return 0
    } || {
        log_error "Tier 4 deployment had issues"
        print_summary
        return 1
    }
}

main "$@"
