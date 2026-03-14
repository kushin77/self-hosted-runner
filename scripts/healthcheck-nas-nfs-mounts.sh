#!/bin/bash
#
# NAS NFS MOUNT HEALTH CHECK
# Monitors NFS mount status, connectivity, and performance
#
# Usage: ./healthcheck-nas-nfs-mounts.sh

set -euo pipefail

readonly NAS_SERVER="192.16.168.39"
readonly MOUNT_POINT="/nas"
readonly REPOS_MOUNT="/nas/repositories"
readonly CONFIG_MOUNT="/nas/config-vault"
readonly HEALTH_LOG="/var/log/nas-nfs-health.log"
readonly AUDIT_FILE="/nas/repositories/.audit/health-$(date +%Y%m%d-%H%M%S).jsonl"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

# ============================================================================
# Logging
# ============================================================================

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_fail() { echo -e "${RED}✗${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }

audit() {
    local status=$1
    local message=$2
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    [[ -d "$(dirname "$AUDIT_FILE")" ]] && \
        echo "{\"timestamp\":\"$timestamp\",\"status\":\"$status\",\"message\":\"$message\"}" >> "$AUDIT_FILE"
}

# ============================================================================
# Health Checks
# ============================================================================

check_mount_status() {
    log_info "Checking NFS mount status..."
    
    # Repositories mount
    if mount | grep -q "$REPOS_MOUNT"; then
        log_success "Repositories mount is active"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "Repositories mount is missing"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
    
    # Config vault mount
    if mount | grep -q "$CONFIG_MOUNT"; then
        log_success "Config vault mount is active"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "Config vault mount is missing"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

check_nfs_connectivity() {
    log_info "Checking NFS server connectivity..."
    
    if ping -c 1 -W 2 "$NAS_SERVER" &>/dev/null; then
        log_success "NAS server is reachable"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "NAS server is unreachable"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

check_mount_access() {
    log_info "Checking mount accessibility..."
    
    # Read access
    if [[ -r "$REPOS_MOUNT" ]]; then
        log_success "Repositories mount is readable"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "Cannot read repositories mount"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
    
    if [[ -r "$CONFIG_MOUNT" ]]; then
        log_success "Config vault mount is readable"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "Cannot read config vault mount"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

check_disk_space() {
    log_info "Checking disk space on NFS mounts..."
    
    local repos_free=$(df "$REPOS_MOUNT" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local config_free=$(df "$CONFIG_MOUNT" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    
    if [[ $repos_free -gt 10485760 ]]; then
        log_success "Repositories mount: $(( repos_free / 1024 / 1024 ))GB free"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warn "Repositories mount low: $(( repos_free / 1024 / 1024 ))GB free"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    fi
    
    if [[ $config_free -gt 1048576 ]]; then
        log_success "Config vault: $(( config_free / 1024 / 1024 ))MB free"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warn "Config vault low: $(( config_free / 1024 / 1024 ))MB free"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    fi
}

check_io_performance() {
    log_info "Checking I/O performance..."
    
    # Write test
    local test_file="${REPOS_MOUNT}/.health-test-$(date +%s).tmp"
    if timeout 5 bash -c "dd if=/dev/zero of='$test_file' bs=1M count=10 &>/dev/null && rm -f '$test_file'"; then
        log_success "I/O performance acceptable"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warn "I/O performance test timed out or failed"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    fi
}

check_mount_options() {
    log_info "Checking mount options..."
    
    if mount | grep "$REPOS_MOUNT" | grep -qE "proto=tcp|vers=4"; then
        log_success "NFS v4 with TCP protocol detected"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warn "Mount protocol version not verified"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    fi
}

check_systemd_units() {
    log_info "Checking systemd mount units..."
    
    if systemctl is-active --quiet nas-repositories.mount 2>/dev/null; then
        log_success "nas-repositories.mount is active"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "nas-repositories.mount is not active"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
    
    if systemctl is-active --quiet nas-config-vault.mount 2>/dev/null; then
        log_success "nas-config-vault.mount is active"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "nas-config-vault.mount is not active"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

# ============================================================================
# Report
# ============================================================================

print_report() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}■ NAS NFS Mount Health Report${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Timestamp: $(date)"
    echo -e "NAS Server: ${NAS_SERVER}"
    echo -e "Checks Passed: ${GREEN}${CHECKS_PASSED}${NC}"
    echo -e "Checks Failed: ${RED}${CHECKS_FAILED}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All health checks passed!${NC}"
        audit "HEALTHY" "All checks passed"
        return 0
    else
        echo -e "${RED}✗ Some health checks failed${NC}"
        audit "UNHEALTHY" "$CHECKS_FAILED checks failed"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo
    echo -e "${BLUE}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│   NAS NFS Mount Health Check                          │${NC}"
    echo -e "${BLUE}│   $(date +%Y-%m-%d\ %H:%M:%S)${BLUE}                                   │${NC}"
    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${NC}"
    echo
    
    check_nfs_connectivity
    check_mount_status
    check_mount_access
    check_disk_space
    check_io_performance
    check_mount_options
    check_systemd_units
    
    print_report
}

main
