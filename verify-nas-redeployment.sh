#!/bin/bash
#
# NAS REDEPLOYMENT VALIDATION & VERIFICATION SCRIPT
# Comprehensive health checks for NAS-based deployment
#
# Usage: ./verify-nas-redeployment.sh [quick|detailed|comprehensive]

set -euo pipefail

# Configuration
readonly NAS_SERVER="192.168.168.39"
readonly WORKER_NODE="192.168.168.42"
readonly DEV_NODE="192.168.168.31"
readonly AUTOMATION_USER="automation"

# Verification mode (default: detailed)
MODE="${1:-detailed}"

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0
CHECKS_TOTAL=0

# ============================================================================
# Helper Functions
# ============================================================================

check_start() {
    local check_name=$1
    echo -e "${BLUE}▶${NC} Checking: $check_name..."
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
}

check_pass() {
    local message=${1:-"OK"}
    echo -e "  ${GREEN}✓${NC} $message"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_fail() {
    local message=${1:-"FAILED"}
    echo -e "  ${RED}✗${NC} $message"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

check_warn() {
    local message=${1:-"WARNING"}
    echo -e "  ${YELLOW}⚠${NC} $message"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
}

print_section() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}■${NC} $1"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_results() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Results: ${GREEN}$CHECKS_PASSED passed${NC}, ${RED}$CHECKS_FAILED failed${NC}, ${YELLOW}$CHECKS_WARNING warnings${NC} (of $CHECKS_TOTAL total)"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All critical checks passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some checks failed - see above for details${NC}"
        return 1
    fi
}

# ============================================================================
# NETWORK & CONNECTIVITY CHECKS
# ============================================================================

verify_network() {
    print_section "NETWORK & CONNECTIVITY VERIFICATION"
    
    # NAS Connectivity
    check_start "NAS server reachability (${NAS_SERVER}:22)"
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${AUTOMATION_USER}@${NAS_SERVER}" "exit 0" &>/dev/null; then
        check_pass "NAS is reachable and SSH working"
    else
        check_fail "Cannot reach NAS at ${NAS_SERVER}"
    fi
    
    # Worker Node Connectivity
    check_start "Worker node reachability (${WORKER_NODE}:22)"
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${AUTOMATION_USER}@${WORKER_NODE}" "exit 0" &>/dev/null; then
        check_pass "Worker node is reachable and SSH working"
    else
        check_fail "Cannot reach worker node at ${WORKER_NODE}"
    fi
    
    # Worker to NAS Connectivity
    check_start "Worker → NAS connectivity"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            ${AUTOMATION_USER}@${NAS_SERVER} exit 0" &>/dev/null; then
        check_pass "Worker can reach NAS (verified)"
    else
        check_fail "Worker cannot reach NAS"
    fi
    
    # DNS Resolution
    check_start "DNS resolution"
    local dns_ok=true
    for host in "${NAS_SERVER}" "${WORKER_NODE}" "${DEV_NODE}"; do
        if ! ping -c 1 -W 2 "$host" &>/dev/null; then
            check_warn "Cannot ping $host"
            dns_ok=false
        fi
    done
    if [[ $dns_ok == true ]]; then
        check_pass "All hosts are reachable via ping"
    fi
}

# ============================================================================
# NAS STORAGE VERIFICATION
# ============================================================================

verify_nas_storage() {
    print_section "NAS STORAGE VERIFICATION"
    
    # NAS Disk Space
    check_start "NAS disk space"
    local nas_disk=$(ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
        "df /repositories 2>/dev/null | tail -1 | awk '{print \$4}'" || echo "0")
    local nas_free_gb=$((nas_disk / 1024 / 1024))
    if [[ $nas_free_gb -gt 50 ]]; then
        check_pass "NAS has sufficient space (${nas_free_gb}GB free)"
    elif [[ $nas_free_gb -gt 20 ]]; then
        check_warn "NAS disk space is moderate (${nas_free_gb}GB free, recommend 50GB+)"
    else
        check_fail "NAS disk space is low (${nas_free_gb}GB free, need 50GB)"
    fi
    
    # NAS Directory Structure
    check_start "NAS directory structure"
    if ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
        "test -d /repositories && test -d /config-vault && test -d /audit-trails"; then
        check_pass "All required NAS directories exist"
    else
        check_warn "Some NAS directories missing (will be created on sync)"
    fi
    
    # NAS Repository Files
    check_start "NAS repository content"
    local nas_files=$(ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
        "find /repositories/self-hosted-runner -type f 2>/dev/null | wc -l" || echo "0")
    if [[ $nas_files -gt 100 ]]; then
        check_pass "NAS repository has ${nas_files} files"
    elif [[ $nas_files -gt 0 ]]; then
        check_warn "NAS repository has only ${nas_files} files (may not be fully synced)"
    else
        check_warn "NAS repository appears empty (sync may be pending)"
    fi
    
    # NAS Config Vault
    check_start "NAS config vault"
    local nas_configs=$(ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
        "find /config-vault -type f 2>/dev/null | wc -l" || echo "0")
    if [[ $nas_configs -gt 0 ]]; then
        check_pass "NAS config vault has ${nas_configs} files"
    else
        check_warn "NAS config vault appears empty"
    fi
}

# ============================================================================
# WORKER NODE VERIFICATION
# ============================================================================

verify_worker_node() {
    print_section "WORKER NODE VERIFICATION"
    
    # Worker Disk Space
    check_start "Worker node disk space"
    local worker_disk=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "df /opt 2>/dev/null | tail -1 | awk '{print \$4}'" || echo "0")
    local worker_free_gb=$((worker_disk / 1024 / 1024))
    if [[ $worker_free_gb -gt 20 ]]; then
        check_pass "Worker has sufficient space (${worker_free_gb}GB free)"
    elif [[ $worker_free_gb -gt 10 ]]; then
        check_warn "Worker disk space is moderate (${worker_free_gb}GB free, recommend 20GB+)"
    else
        check_fail "Worker disk space is low (${worker_free_gb}GB free, need 20GB)"
    fi
    
    # Systemd Services
    check_start "NAS worker sync service"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl is-active --quiet nas-worker-sync.service" 2>/dev/null; then
        check_pass "nas-worker-sync.service is active"
    else
        check_warn "nas-worker-sync.service is not active (may be waiting for timer)"
    fi
    
    check_start "NAS worker sync timer"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl is-active --quiet nas-worker-sync.timer"; then
        check_pass "nas-worker-sync.timer is active (runs every 30 min)"
    else
        check_fail "nas-worker-sync.timer is not active"
    fi
    
    check_start "NAS health check timer"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl is-active --quiet nas-worker-healthcheck.timer"; then
        check_pass "nas-worker-healthcheck.timer is active (runs every 15 min)"
    else
        check_fail "nas-worker-healthcheck.timer is not active"
    fi
    
    check_start "NAS integration target"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl is-active --quiet nas-integration.target"; then
        check_pass "nas-integration.target is active"
    else
        check_warn "nas-integration.target is not active"
    fi
    
    # Systemd Unit Files
    check_start "Systemd unit files installed"
    local units_installed=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "ls /etc/systemd/system/nas-*.* 2>/dev/null | wc -l" || echo "0")
    if [[ $units_installed -ge 5 ]]; then
        check_pass "All ${units_installed} NAS systemd units are installed"
    else
        check_warn "Only ${units_installed} NAS systemd units found (expected 5+)"
    fi
}

# ============================================================================
# SYNC STATUS VERIFICATION
# ============================================================================

verify_sync_status() {
    print_section "SYNC STATUS VERIFICATION"
    
    # Worker Sync Directory
    check_start "Worker sync directory exists"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" "test -d /opt/nas-sync"; then
        check_pass "/opt/nas-sync directory exists on worker"
    else
        check_warning "/opt/nas-sync directory not found (sync not yet run)"
    fi
    
    # Worker Synced Files
    check_start "Worker synced files"
    local worker_files=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "find /opt/nas-sync -type f 2>/dev/null | wc -l" || echo "0")
    if [[ $worker_files -gt 100 ]]; then
        check_pass "Worker has ${worker_files} synced files"
    elif [[ $worker_files -gt 0 ]]; then
        check_warn "Worker has only ${worker_files} synced files (sync may be in progress)"
    else
        check_warn "Worker sync directory appears empty (sync hasn't run yet)"
    fi
    
    # Last Sync Time
    check_start "Last sync timestamp"
    local last_sync=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "stat -c %y /opt/nas-sync 2>/dev/null | cut -d' ' -f1-2" || echo "unknown")
    check_pass "Last sync: $last_sync"
    
    # Audit Trail
    check_start "Sync audit trail"
    local audit_entries=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "wc -l /opt/nas-sync/audit/*.jsonl 2>/dev/null | tail -1 | awk '{print \$1}'" || echo "0")
    if [[ $audit_entries -gt 0 ]]; then
        check_pass "Audit trail has ${audit_entries} entries"
    else
        check_warn "Audit trail not found or empty (first sync may be pending)"
    fi
}

# ============================================================================
# APPLICATION VERIFICATION
# ============================================================================

verify_applications() {
    print_section "APPLICATION & SERVICE VERIFICATION"
    
    # Portal availability
    check_start "Portal API health"
    if curl -s -o /dev/null -w "%{http_code}" "http://${WORKER_NODE}:5000/health" 2>/dev/null | grep -qE "200|302"; then
        check_pass "Portal API is accessible"
    else
        check_warn "Portal API health check inconclusive"
    fi
    
    # Kubernetes/Docker services
    check_start "Container services"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "docker ps --format table 2>/dev/null | wc -l" | grep -qE "^[2-9]"; then
        check_pass "Container services are running"
    else
        check_warn "Container services status unclear"
    fi
}

# ============================================================================
# SECURITY VERIFICATION
# ============================================================================

verify_security() {
    print_section "SECURITY VERIFICATION"
    
    # SSH Key Security
    check_start "SSH key permissions"
    local key_perms=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "stat -c %a ~/.ssh/id_ed25519 2>/dev/null" || echo "unknown")
    if [[ "$key_perms" == "600" ]]; then
        check_pass "SSH key permissions are correct (600)"
    else
        check_warn "SSH key permissions may not be secure (${key_perms})"
    fi
    
    # Credentials Directory Permissions
    check_start "Credentials directory permissions"
    local cred_perms=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "stat -c %a /opt/nas-sync/credentials 2>/dev/null" || echo "missing")
    if [[ "$cred_perms" == "700" ]]; then
        check_pass "Credentials directory permissions are secure (700)"
    elif [[ "$cred_perms" == "missing" ]]; then
        check_warn "Credentials directory not found (may not be synced yet)"
    else
        check_warn "Credentials directory permissions may not be secure (${cred_perms})"
    fi
    
    # GSM Access
    check_start "GCP Secret Manager access"
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "gcloud secrets list --limit=1 &>/dev/null"; then
        check_pass "Worker can access GCP Secret Manager"
    else
        check_warn "Cannot verify GSM access (service account may not be configured)"
    fi
}

# ============================================================================
# DEPLOYMENT LOG VERIFICATION
# ============================================================================

verify_deployment_logs() {
    print_section "DEPLOYMENT LOG VERIFICATION"
    
    local log_dir="/home/akushnir/self-hosted-runner/.deployment-logs"
    
    # Deployment Log
    check_start "Deployment log exists"
    if [[ -d "$log_dir" ]] && ls "$log_dir"/nas-full-redeployment-*.log &>/dev/null; then
        local latest_log=$(ls -t "$log_dir"/nas-full-redeployment-*.log | head -1)
        check_pass "Deployment log found: $latest_log"
        
        # Check for errors in log
        check_start "Checking for errors in deployment log"
        if grep -q "\\[ERROR\\]" "$latest_log"; then
            check_fail "Deployment log contains errors"
            echo "    First error:"
            grep "\\[ERROR\\]" "$latest_log" | head -1 | sed 's/^/    /'
        else
            check_pass "No errors in deployment log"
        fi
    else
        check_warn "Deployment log not found (deployment may not have run yet)"
    fi
    
    # Audit Trail
    check_start "Audit trail exists"
    if ls "$log_dir"/audit-trail-*.jsonl &>/dev/null; then
        local latest_audit=$(ls -t "$log_dir"/audit-trail-*.jsonl | head -1)
        local audit_lines=$(wc -l < "$latest_audit")
        check_pass "Audit trail found with ${audit_lines} events"
    else
        check_warn "Audit trail not found"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   NAS REDEPLOYMENT VERIFICATION & HEALTH CHECK        ║${NC}"
    echo -e "${BLUE}║   Mode: ${MODE:0:15}${BLUE}$(printf '%*s' $((38 - ${#MODE})) '')║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Run verification checks based on mode
    case "$MODE" in
        quick)
            verify_network
            verify_worker_node
            ;;
        detailed|*)
            verify_network
            verify_nas_storage
            verify_worker_node
            verify_sync_status
            verify_deployment_logs
            ;;
        comprehensive)
            verify_network
            verify_nas_storage
            verify_worker_node
            verify_sync_status
            verify_applications
            verify_security
            verify_deployment_logs
            ;;
    esac
    
    # Print summary
    print_results
}

main
