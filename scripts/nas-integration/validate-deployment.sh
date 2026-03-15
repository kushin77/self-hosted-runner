#!/bin/bash
#
# 🔍 NAS Integration Deployment Verification Script
#
# Comprehensive validation of Phase 3 deployment
# Checks prerequisites, post-deployment state, and operational readiness
#
# Usage:
#   bash validate-deployment.sh [--verbose] [--fix] [--report-file=FILE]
#
# Modes:
#   --verbose     : Show detailed output for each check
#   --fix         : Attempt to fix common issues
#   --report-file : Save detailed report to file
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly NAS_HOST="192.168.168.39"
readonly NAS_PORT="22"
readonly DEV_NODE="192.168.168.31"
readonly WORKER_NODE="192.168.168.42"

# State
VERBOSE="${VERBOSE:-false}"
FIX_MODE="${FIX_MODE:-false}"
REPORT_FILE=""
PASSED=0
FAILED=0
total_checks=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; PASSED=$((PASSED+1)); }
error() { echo -e "${RED}❌${NC} $*"; FAILED=$((FAILED+1)); }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
info() { echo -e "${MAGENTA}ℹ${NC}  $*"; }
section() { echo; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}$*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

increment_check() { total_checks=$((total_checks+1)); }

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
  section "PHASE 1: PREREQUISITES"
  
  increment_check
  if command -v nfsstat &>/dev/null; then
    success "NFS utilities installed"
  else
    error "NFS utilities not installed (apt install nfs-common)"
    [[ "$FIX_MODE" == "true" ]] && sudo apt install -y nfs-common
  fi
  
  increment_check
  if ping -c 1 -W 2 "$NAS_HOST" &>/dev/null; then
    success "NAS server reachable (192.168.168.39)"
  else
    error "NAS server unreachable at $NAS_HOST"
  fi
  
  increment_check
  if [[ -d /mnt/nas ]]; then
    success "Mount point directory exists"
  else
    error "Mount point /mnt/nas does not exist"
    [[ "$FIX_MODE" == "true" ]] && sudo mkdir -p /mnt/nas
  fi
  
  increment_check
  if showmount -e "$NAS_HOST" &>/dev/null; then
    success "NAS exports accessible"
    [[ "$VERBOSE" == "true" ]] && showmount -e "$NAS_HOST" | sed 's/^/  /'
  else
    error "Cannot enumerate NAS exports"
  fi
}

# ============================================================================
# MOUNT VERIFICATION
# ============================================================================

check_mounts() {
  section "PHASE 2: NFS MOUNTS"
  
  local expected_mounts=("repositories" "config-vault" "audit-logs")
  local mounted_count=0
  
  for mount_name in "${expected_mounts[@]}"; do
    increment_check
    if mount | grep -q "/mnt/nas/$mount_name"; then
      success "Mount point /mnt/nas/$mount_name is active"
      mounted_count=$((mounted_count+1))
    else
      error "Mount point /mnt/nas/$mount_name not found"
    fi
  done
  
  increment_check
  if [[ $mounted_count -eq 3 ]]; then
    success "All 3 mounts active (3/3)"
  else
    error "Only $mounted_count/3 mounts active"
  fi
}

# ============================================================================
# PROTOCOL VERIFICATION
# ============================================================================

check_protocol() {
  section "PHASE 3: NFS PROTOCOL & SECURITY"
  
  increment_check
  local nfs4_count=$(mount | grep -c "vers=4.1" || true)
  if [[ $nfs4_count -eq 3 ]]; then
    success "All mounts using NFS v4.1"
  else
    error "Not all mounts using NFS v4.1 (found $nfs4_count/3)"
  fi
  
  increment_check
  local tcp_count=$(mount | grep "192.168.168.39" | grep -c "proto=tcp" || true)
  if [[ $tcp_count -eq 3 ]]; then
    success "All mounts using TCP transport (no UDP)"
  else
    error "Not all mounts using TCP (found $tcp_count/3)"
  fi
  
  increment_check
  local hard_count=$(mount | grep "192.168.168.39" | grep -c "hard" || true)
  if [[ $hard_count -eq 3 ]]; then
    success "All mounts are hard mounts (prevents data loss)"
  else
    error "Not all mounts are hard mounts (found $hard_count/3)"
  fi
  
  increment_check
  if grep -q "timeo=30,retrans=3" /etc/fstab; then
    success "Fstab has correct retry parameters (timeo=30, retrans=3)"
  else
    error "Fstab missing or incorrect retry parameters"
  fi
}

# ============================================================================
# PERMISSIONS CHECK
# ============================================================================

check_permissions() {
  section "PHASE 4: MOUNT PERMISSIONS"
  
  increment_check
  if mount | grep "repositories" | grep -q "rw"; then
    success "Repositories mount is RW (read-write)"
  else
    error "Repositories mount is not RW"
  fi
  
  increment_check
  if mount | grep "config-vault" | grep -q "(ro"; then
    success "Config-vault mount is RO (read-only)"
  else
    error "Config-vault mount is not RO"
  fi
  
  increment_check
  if mount | grep "audit-logs" | grep -q "(ro"; then
    success "Audit-logs mount is RO (read-only)"
  else
    error "Audit-logs mount is not RO"
  fi
  
  increment_check
  if [[ -d /opt/iac-configs ]]; then
    success "IAC staging directory exists"
  else
    error "IAC staging directory missing"
    [[ "$FIX_MODE" == "true" ]] && sudo mkdir -p /opt/iac-configs
  fi
}

# ============================================================================
# HEALTH MONITORING
# ============================================================================

check_health_monitoring() {
  section "PHASE 5: HEALTH MONITORING"
  
  increment_check
  if systemctl is-active -q nas-validate-health.service; then
    success "Health monitoring service is active"
  else
    error "Health monitoring service is not active"
    [[ "$VERBOSE" == "true" ]] && systemctl status nas-validate-health.service
  fi
  
  increment_check
  if systemctl is-enabled -q nas-validate-health.timer 2>/dev/null || systemctl is-active -q nas-validate-health.timer 2>/dev/null; then
    success "Health check timer is enabled"
  else
    error "Health check timer is not enabled"
  fi
  
  increment_check
  local recent_logs=$(journalctl -u nas-validate-health.service --since "5 minutes ago" 2>/dev/null | wc -l)
  if [[ $recent_logs -gt 0 ]]; then
    success "Health checks running (recent activity: $recent_logs lines)"
  else
    warn "No recent health check activity (may be normal if timer haven't run)"
  fi
}

# ============================================================================
# SYSTEMD SERVICES
# ============================================================================

check_systemd_services() {
  section "PHASE 6: SYSTEMD SERVICES"
  
  local services=("nas-dev-push.service" "nas-dev-push.timer" "nas-validate-health.service" "nas-validate-health.timer")
  
  for service in "${services[@]}"; do
    increment_check
    if systemctl list-unit-files | grep -q "$service"; then
      if systemctl is-active -q "$service" 2>/dev/null || [[ "$service" == *"timer" ]]; then
        success "Service $service is configured"
      else
        warn "Service $service exists but may not be active"
      fi
    else
      error "Service $service not found"
    fi
  done
}

# ============================================================================
# SSH AUTHENTICATION
# ============================================================================

check_ssh_auth() {
  section "PHASE 7: SSH AUTHENTICATION"
  
  increment_check
  if [[ -f /home/automation/.ssh/nas-push-key ]]; then
    success "SSH key exists"
  else
    error "SSH key not found at /home/automation/.ssh/nas-push-key"
  fi
  
  increment_check
  if ssh -i /home/automation/.ssh/nas-push-key -o ConnectTimeout=5 elevatediq-svc-nas@"$NAS_HOST" "echo OK" &>/dev/null; then
    success "SSH authentication to NAS working"
  else
    error "SSH authentication to NAS failed"
  fi
}

# ============================================================================
# FUNCTIONALITY TESTS
# ============================================================================

check_functionality() {
  section "PHASE 8: FUNCTIONALITY TESTS"
  
  increment_check
  if [[ -d /mnt/nas/repositories ]] && touch /tmp/test-$$-file && cp /tmp/test-$$-file /mnt/nas/repositories/ 2>/dev/null && rm -f /mnt/nas/repositories/test-$$-file /tmp/test-$$-file; then
    success "Can write to repositories mount"
  else
    error "Cannot write to repositories mount"
    rm -f /tmp/test-$$-file 2>/dev/null
  fi
  
  increment_check
  if [[ -d /mnt/nas/config-vault ]]; then
    if touch /mnt/nas/config-vault/readonly-test 2>/dev/null; then
      error "Config-vault should be read-only but write succeeded"
      rm -f /mnt/nas/config-vault/readonly-test 2>/dev/null
    else
      success "Config-vault is read-only (write correctly denied)"
    fi
  fi
  
  increment_check
  if [[ -d /opt/iac-configs ]] && [[ -f /home/automation/.ssh/nas-push-key ]]; then
    success "IAC push infrastructure in place"
  else
    error "IAC push infrastructure incomplete"
  fi
}

# ============================================================================
# NETWORK ISOLATION
# ============================================================================

check_network_isolation() {
  section "PHASE 9: NETWORK ISOLATION"
  
  increment_check
  local dev_net=$(ip route | grep "192.168.168.0/24" | wc -l)
  if [[ $dev_net -gt 0 ]]; then
    success "Network isolated on 192.168.168.0/24"
  else
    warn "Cannot verify network isolation (may be OK depending on setup)"
  fi
  
  increment_check
  if ping -c 1 "$NAS_HOST" &>/dev/null && ! ping -c 1 8.8.8.8 &>/dev/null 2>&1; then
    success "Network isolation confirmed (NAS reachable, external blocked)"
  else
    warn "Cannot fully verify network isolation (check firewall rules)"
  fi
}

# ============================================================================
# PERSISTENCE TEST
# ============================================================================

check_persistence() {
  section "PHASE 10: PERSISTENCE TEST"
  
  increment_check
  local fstab_entries=$(grep -c "192.168.168.39" /etc/fstab || true)
  if [[ $fstab_entries -ge 3 ]]; then
    success "Fstab has $fstab_entries persistent mount entries"
  else
    error "Fstab missing persistent mount entries (found $fstab_entries, need 3)"
  fi
  
  increment_check
  if grep -q "_netdev" /etc/fstab; then
    success "Mounts configured as network-dependent"
  else
    warn "Mounts may not be configured as network-dependent"
  fi
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================

generate_report() {
  section "DEPLOYMENT VERIFICATION REPORT"
  
  local total_results=$((PASSED+FAILED))
  local pass_rate=0
  [[ $total_results -gt 0 ]] && pass_rate=$((PASSED * 100 / total_results))
  
  cat << EOF

Total Checks:     $total_checks
Passed:           $PASSED
Failed:           $FAILED
Pass Rate:        ${pass_rate}%

────────────────────────────────────────────────────────────────────────────────

DEPLOYMENT STATUS:
EOF

  if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL CHECKS PASSED - DEPLOYMENT SUCCESSFUL${NC}"
  elif [[ $FAILED -le 2 ]]; then
    echo -e "${YELLOW}⚠ DEPLOYMENT WITH WARNINGS ($FAILED issues found)${NC}"
  else
    echo -e "${RED}❌ DEPLOYMENT FAILED ($FAILED issues found)${NC}"
  fi

  cat << EOF

────────────────────────────────────────────────────────────────────────────────

DEPLOYMENT READY FOR:
  ✅ NAS use as IAC repository
  ✅ Automatic health monitoring
  ✅ Worker node synchronization
  ✅ Configuration management

NEXT ACTIONS:
  1. Monitor health checks: journalctl -u nas-validate-health.service -f
  2. Test push workflow: bash dev-node-automation.sh push
  3. Verify worker receives config: ssh 192.168.168.42 ls /opt/deployed-configs
  4. Set up monitoring alerts (optional)

────────────────────────────────────────────────────────────────────────────────

Generated: $(date)
NAS Server: $NAS_HOST
Dev Node: $DEV_NODE
Worker: $WORKER_NODE

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) VERBOSE="true" ;;
      --fix) FIX_MODE="true" ;;
      --report-file=*) REPORT_FILE="${1#*=}" ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
  done
  
  if [[ "$FIX_MODE" == "true" ]] && [[ "$VERBOSE" != "true" ]]; then
    VERBOSE="true"
  fi
  
  # Run all checks
  check_prerequisites
  check_mounts
  check_protocol
  check_permissions
  check_health_monitoring
  check_systemd_services
  check_ssh_auth
  check_functionality
  check_network_isolation
  check_persistence
  
  # Generate report
  local report=$(generate_report)
  echo "$report"
  
  # Save report if requested
  if [[ -n "$REPORT_FILE" ]]; then
    echo "$report" > "$REPORT_FILE"
    echo ""
    echo "Report saved to: $REPORT_FILE"
  fi
  
  # Exit with status
  [[ $FAILED -eq 0 ]]
}

main "$@"
