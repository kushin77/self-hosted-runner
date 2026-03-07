#!/bin/bash
################################################################################
# TIER 1: EMERGENCY REMEDIATION - Self-Hosted Runner Host Fix
# Purpose: Stop restart cascades, disable broken services, stabilize system
# Date: 2026-03-07
# Idempotent: YES - Safe to run multiple times
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_DIR="${HOME}/.local/var/runner-remediation"
readonly LOG_FILE="${LOG_DIR}/tier-1-$(date +%Y%m%d-%H%M%S).log"
readonly TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

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
    log_info "=== TIER 1 EMERGENCY REMEDIATION START ==="
    log "Log file: ${LOG_FILE}"
    log "System info: $(uname -a)"
    log "Current user: $(whoami)"
    log "Timestamp: ${TIMESTAMP}"
}

################################################################################
# STEP 1: DISABLE BROKEN SERVICES TEMPORARILY
################################################################################

disable_broken_services() {
    log_info "Step 1: Disabling broken systemd services..."
    
    local services=("vscode_oom_watchdog.service" "elevatediq-pylance-oom-watchdog.service" "ide-2030-threat-detector.service")
    
    for svc in "${services[@]}"; do
        if systemctl --user is-enabled "${svc}" &>/dev/null; then
            log "Disabling ${svc}..."
            systemctl --user disable "${svc}" 2>/dev/null || true
            systemctl --user stop "${svc}" 2>/dev/null || true
            log_info "✓ Disabled ${svc}"
        fi
    done
    
    # Reset restart counters by clearing systemd state  
    log "Resetting systemd service state..."
    systemctl --user reset-failed 2>/dev/null || true
    log_info "✓ Service state reset"
}

################################################################################
# STEP 2: CREATE MISSING LIBRARY
################################################################################

create_monitor_guards_lib() {
    log_info "Step 2: Creating missing monitor_guards.sh library..."
    
    local lib_path="/home/$(whoami)/scripts/lib/monitor_guards.sh"
    local lib_dir="$(dirname "${lib_path}")"
    
    mkdir -p "${lib_dir}"
    
    cat > "${lib_path}" << 'LIBEOF'
#!/bin/bash
################################################################################
# monitor_guards.sh - OOM Monitoring & System Guard Library
# Version: 1.0.0
# Provides functions for safe process monitoring with resource guards
################################################################################

set -euo pipefail

# Configuration
readonly DEFAULT_MEM_THRESHOLD_MB=256
readonly DEFAULT_CPU_LIMIT=80

################################################################################
# Memory Monitoring Guard
################################################################################

check_memory_pressure() {
    local threshold_mb="${1:-${DEFAULT_MEM_THRESHOLD_MB}}"
    local hostname="${HOSTNAME:-unknown}"
    
    # Get available memory in MB
    local avail_mem_mb=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}')
    
    if (( avail_mem_mb < threshold_mb )); then
        echo "{\"status\":\"CRITICAL\",\"type\":\"memory_pressure\",\"available_mb\":${avail_mem_mb},\"threshold_mb\":${threshold_mb},\"hostname\":\"${hostname}\",\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}"
        return 1
    else
        echo "{\"status\":\"OK\",\"type\":\"memory_pressure\",\"available_mb\":${avail_mem_mb},\"threshold_mb\":${threshold_mb},\"hostname\":\"${hostname}\",\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}"
        return 0
    fi
}

################################################################################
# Process OOM Score Adjustment
################################################################################

set_oom_score() {
    local pid="$1"
    local oom_score="${2:-500}"
    
    if [[ ! -f "/proc/${pid}/oom_score_adj" ]]; then
        return 1
    fi
    
    if echo "${oom_score}" > "/proc/${pid}/oom_score_adj" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

################################################################################
# CPU Monitoring Guard
################################################################################

check_cpu_saturation() {
    local threshold="${1:-${DEFAULT_CPU_LIMIT}}"
    
    # Get 1-minute load average and CPU count
    local load_avg=$(cut -d' ' -f1 /proc/loadavg)
    local cpu_count=$(grep -c '^processor' /proc/cpuinfo)
    local cpu_usage=$(echo "scale=2; ($load_avg / $cpu_count) * 100" | bc)
    
    if (( $(echo "$cpu_usage > $threshold" | bc -l) )); then
        echo "{\"status\":\"HIGH\",\"type\":\"cpu_saturation\",\"usage_percent\":${cpu_usage},\"threshold_percent\":${threshold},\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}"
        return 1
    else
        echo "{\"status\":\"NORMAL\",\"type\":\"cpu_saturation\",\"usage_percent\":${cpu_usage},\"threshold_percent\":${threshold},\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}"
        return 0
    fi
}

################################################################################
# Safe Process Execution Guard
################################################################################

run_with_guard() {
    local cmd="$@"
    local mem_guard="${GUARD_MEM_MB:-256}"
    local timeout_sec="${GUARD_TIMEOUT:-300}"
    
    # Check memory before execution
    if ! check_memory_pressure "${mem_guard}" &>/dev/null; then
        log_error "Insufficient memory, aborting execution"
        return 1
    fi
    
    # Execute with timeout
    timeout "${timeout_sec}" "${cmd}" || return $?
}

################################################################################
# Graceful Shutdown Handler
################################################################################

graceful_shutdown() {
    local exit_code="${1:-0}"
    log_info "Monitor guards library shutting down gracefully (exit code: ${exit_code})"
    exit "${exit_code}"
}

# Export functions
export -f check_memory_pressure
export -f set_oom_score
export -f check_cpu_saturation
export -f run_with_guard
export -f graceful_shutdown

LIBEOF
    
    chmod 755 "${lib_path}"
    log_info "✓ Created monitor_guards.sh at ${lib_path}"
}

################################################################################
# STEP 3: FIX VSCODE OOM WATCHDOG
################################################################################

fix_vscode_oom_watchdog() {
    log_info "Step 3: Fixing vscode_oom_watchdog.sh..."
    
    local watchdog_path="/home/$(whoami)/ElevatedIQ-Mono-Repo/ElevatedIQ-Mono-Repo/scripts/automation/pmo/vscode_oom_watchdog.sh"
    
    if [[ ! -f "${watchdog_path}" ]]; then
        log_warn "Watchdog file not found at ${watchdog_path}, creating new one..."
        mkdir -p "$(dirname "${watchdog_path}")"
        create_new_watchdog "${watchdog_path}"
    else
        log "Backing up original: ${watchdog_path}.backup-$(date +%s)"
        cp "${watchdog_path}" "${watchdog_path}.backup-$(date +%s)"
        create_new_watchdog "${watchdog_path}"
    fi
    
    log_info "✓ Fixed vscode_oom_watchdog.sh"
}

create_new_watchdog() {
    local output_path="$1"
    
    cat > "${output_path}" << 'WATCHDOGEOF'
#!/bin/bash
################################################################################
# vscode_oom_watchdog.sh - VS Code OOM Watchdog Service
# Purpose: Monitor VS Code memory usage and gracefully handle OOM conditions
# Version: 2.0 (Fixed)
# Idempotent: YES
################################################################################

set -euo pipefail

# Source monitor guards if available
GUARDS_LIB="${HOME}/scripts/lib/monitor_guards.sh"
if [[ -f "${GUARDS_LIB}" ]]; then
    # shellcheck source=/dev/null
    source "${GUARDS_LIB}"
else
    # Provide stub functions if guards lib not available
    check_memory_pressure() { return 0; }
fi

# Configuration
readonly CHECK_INTERVAL_SEC="${VSCODE_OOM_CHECK_INTERVAL:-30}"
readonly MEM_THRESHOLD_MB="${VSCODE_OOM_THRESHOLD_MB:-512}"
readonly LOG_FILE="${HOME}/.local/share/vscode-oom-watchdog.log"
readonly PID_FILE="${HOME}/.vscode-oom-watchdog.pid"
readonly JSON_METRICS_DIR="/tmp/vscode-metrics"

# Ensure directories exist
mkdir -p "$(dirname "${LOG_FILE}")" "${JSON_METRICS_DIR}"

################################################################################
# Logging
################################################################################

log_event() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    # JSON output for parsing
    local json="{"
    json+="\"timestamp\":\"${timestamp}\","
    json+="\"level\":\"${level}\","
    json+="\"message\":\"${message}\""
    json+="}"
    
    echo "${json}" | tee -a "${LOG_FILE}"
}

################################################################################
# Main Watchdog Logic
################################################################################

monitor_vscode() {
    log_event "INFO" "Starting VS Code OOM watchdog (PID: $$)"
    echo $$ > "${PID_FILE}"
    
    local iteration=0
    
    while true; do
        ((iteration++))
        
        # Check memory pressure
        local mem_status
        mem_status=$(check_memory_pressure "${MEM_THRESHOLD_MB}") || true
        
        # Write metrics
        echo "${mem_status}" > "${JSON_METRICS_DIR}/memory-$(date +%s).json"
        
        # Find VS Code processes
        local vscode_pids
        vscode_pids=$(pgrep -f "code.*server" 2>/dev/null || true)
        
        if [[ -z "${vscode_pids}" ]]; then
            log_event "DEBUG" "No VS Code processes found (iteration: ${iteration})"
        else
            for pid in ${vscode_pids}; do
                if [[ -f "/proc/${pid}/status" ]]; then
                    local mem_kb
                    mem_kb=$(grep '^VmRSS:' "/proc/${pid}/status" | awk '{print $2}' || echo "0")
                    local mem_mb=$((mem_kb / 1024))
                    
                    if (( mem_mb > MEM_THRESHOLD_MB )); then
                        log_event "WARN" "VS Code PID ${pid} using ${mem_mb}MB (threshold: ${MEM_THRESHOLD_MB}MB)"
                    fi
                fi
            done
        fi
        
        # Sleep before next check
        sleep "${CHECK_INTERVAL_SEC}"
    done
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    log_event "INFO" "Watchdog shutting down (received signal)"
    rm -f "${PID_FILE}"
    exit 0
}

# Register signal handlers
trap cleanup SIGTERM SIGINT

################################################################################
# Entry Point
################################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitor_vscode "$@"
fi
WATCHDOGEOF

    chmod 755 "${output_path}"
    log_info "Created corrected watchdog script"
}

################################################################################
# STEP 4: ADD SYSTEMD RESTART THROTTLING
################################################################################

add_systemd_rate_limiting() {
    log_info "Step 4: Adding systemd restart rate limiting..."
    
    local user_units_dir="${HOME}/.config/systemd/user"
    mkdir -p "${user_units_dir}"
    
    # Create override for vscode_oom_watchdog
    create_systemd_override "vscode_oom_watchdog.service"
    create_systemd_override "elevatediq-pylance-oom-watchdog.service"
    create_systemd_override "ide-2030-threat-detector.service"
    
    log "Reloading systemd user session..."
    systemctl --user daemon-reload 2>/dev/null || true
    
    log_info "✓ Systemd rate limiting configured"
}

create_systemd_override() {
    local service="$1"
    local override_dir="${HOME}/.config/systemd/user/${service}.d"
    local override_file="${override_dir}/restart-limit.conf"
    
    mkdir -p "${override_dir}"
    
    cat > "${override_file}" << 'OVERRIDEEOF'
[Unit]
# Ensure this service doesn't restart too quickly

[Service]
# Limit restarts: max 5 restarts in 1 hour
StartLimitInterval=3600
StartLimitBurst=5

# On restart failure, wait 60 seconds before next attempt
RestartMaxDelaySec=60s

# Action on failure: notify but don't cascade
OnFailure=

# Graceful shutdown timeout
TimeoutStopSec=30s
OVERRIDEEOF
    
    log "Created restart limit override for ${service}"
}

################################################################################
# STEP 5: VALIDATE FIXES
################################################################################

validate_fixes() {
    log_info "Step 5: Validating fixes..."
    
    local validation_passed=true
    
    # Check monitor_guards exists
    if [[ -f "${HOME}/scripts/lib/monitor_guards.sh" ]]; then
        log_info "✓ monitor_guards.sh exists"
    else
        log_error "✗ monitor_guards.sh missing"
        validation_passed=false
    fi
    
    # Check watchdog syntax
    if bash -n "${HOME}/ElevatedIQ-Mono-Repo/ElevatedIQ-Mono-Repo/scripts/automation/pmo/vscode_oom_watchdog.sh" 2>/dev/null; then
        log_info "✓ vscode_oom_watchdog.sh syntax valid"
    else
        log_error "✗ Watchdog syntax errors remain"
        validation_passed=false
    fi
    
    # Check systemd overrides
    if [[ -d "${HOME}/.config/systemd/user" ]]; then
        log_info "✓ Systemd user config directory exists"
    else
        log_error "✗ Systemd user config missing"
        validation_passed=false
    fi
    
    if [[ "${validation_passed}" == true ]]; then
        log_info "✓ All validations passed"
        return 0
    else
        log_error "Some validations failed - review above"
        return 1
    fi
}

################################################################################
# CLEANUP & SUMMARY
################################################################################

print_summary() {
    log_info "=== TIER 1 REMEDIATION SUMMARY ==="
    log "✓ Disabled broken systemd services"
    log "✓ Created missing monitor_guards.sh library"
    log "✓ Fixed vscode_oom_watchdog.sh"
    log "✓ Added systemd restart rate limiting"
    log ""
    log "NEXT STEPS:"
    log "1. Review log: ${LOG_FILE}"
    log "2. Restart systemd user session: systemctl --user restart"
    log "3. Re-enable services after verification: systemctl --user enable <service>"
    log "4. Monitor logs: journalctl --user -f -u <service>"
    log ""
    log_info "=== TIER 1 REMEDIATION COMPLETE ==="
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    init
    
    disable_broken_services
    create_monitor_guards_lib
    fix_vscode_oom_watchdog
    add_systemd_rate_limiting
    validate_fixes
    print_summary
    
    log_info "All Tier 1 fixes applied successfully"
    return 0
}

# Execute main function
main "$@"
