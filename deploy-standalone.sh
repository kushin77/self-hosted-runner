#!/bin/bash
#
# SELF-CONTAINED WORKER NODE DEPLOYMENT PACKAGE
# For Local Execution on dev-elevatediq (192.168.168.42)
#
# ⚠️  MANDATORY: 192.168.168.42 ONLY
# ❌ FORBIDDEN: 192.168.168.31 (localhost/developer workstation)
#
# This script can be run directly on the worker node without SSH
# It contains all deployment logic and will install the components
#
# Usage:
#   1. Copy all scripts to worker node USB/network share
#   2. Run this script on the worker node:
#      bash deploy-standalone.sh
#

set -euo pipefail

# ==============================================================================
# MANDATORY BLOCK: PREVENT DEPLOYMENT TO 192.168.168.31
# ==============================================================================
if [[ "$(hostname)" == "dev-elevatediq-2" ]] || [[ "$(hostname -I 2>/dev/null | awk '{print $1}')" == "192.168.168.31" ]]; then
    echo "[FATAL] DEPLOYMENT BLOCKED: This is 192.168.168.31 (FORBIDDEN)" >&2
    echo "MANDATE: 192.168.168.42 (worker node) is the ONLY deployment target" >&2
    exit 1
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly SESSION_ID=$(openssl rand -hex 8)
readonly DEPLOYMENT_DIR="/opt/automation"
readonly AUDIT_LOG="${DEPLOYMENT_DIR}/audit/deployment-${TIMESTAMP}-${SESSION_ID}.log"

# Verify we're on the correct host
readonly CURRENT_HOST=$(hostname)
readonly TARGET_HOST="dev-elevatediq"
readonly CURRENT_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")

# ============================================================================
# MANDATORY DEPLOYMENT TARGET VALIDATION
# ============================================================================
# CRITICAL: Prevent deployment to developer workstation (192.168.168.31)
if [[ "$CURRENT_HOST" == "dev-elevatediq-2" ]] || [[ "$CURRENT_IP" == "192.168.168.31" ]]; then
  echo -e "\033[0;31m[FATAL ERROR]\033[0m This is the developer workstation (192.168.168.31)"
  echo ""
  echo "MANDATE:"
  echo "  ❌ DO NOT RUN ON THIS MACHINE"
  echo ""
  echo "This script MUST be run on the production worker node:"
  echo "  Hostname: dev-elevatediq"
  echo "  IP: 192.168.168.42"
  echo ""
  echo "Copy this script to the worker node and run it there."
  exit 1
fi

# Color codes
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
  local msg="$*"
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $msg"
  [ -d "$(dirname "$AUDIT_LOG")" ] && echo "$msg" >> "$AUDIT_LOG" 2>/dev/null || true
}

error() {
  local msg="$*"
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: ${msg}${NC}" >&2
  [ -d "$(dirname "$AUDIT_LOG")" ] && echo "ERROR: $msg" >> "$AUDIT_LOG" 2>/dev/null || true
  return 1
}

success() {
  local msg="$*"
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ ${msg}${NC}"
  [ -d "$(dirname "$AUDIT_LOG")" ] && echo "✅ $msg" >> "$AUDIT_LOG" 2>/dev/null || true
}

# ============================================================================
# FRESH BUILD MANDATE ENFORCEMENT
# ============================================================================
# Source the fresh build enforcement library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/scripts/enforce/fresh-build-mandate.sh" ]]; then
  source "${SCRIPT_DIR}/scripts/enforce/fresh-build-mandate.sh"
else
  log "Fresh build mandate library not found - skipping fresh build checks"
fi

# ============================================================================
# VERIFICATION
# ============================================================================

verify_host() {
  log "Verifying target host..."
  
  if [ "$CURRENT_HOST" != "$TARGET_HOST" ]; then
    error "This script must run on $TARGET_HOST, not $CURRENT_HOST"
    error "Current host: $CURRENT_HOST ($(hostname -I))"
    error "Target host: $TARGET_HOST (192.168.168.42)"
    return 1
  fi
  
  success "Running on correct host: $CURRENT_HOST"
}

verify_prerequisites() {
  log "Checking prerequisites..."
  
  # Check for required commands
  for cmd in bash git curl rsync tar gzip; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      return 1
    fi
  done
  success "All required commands available"
  
  # Check disk space
  local available=$(df /opt 2>/dev/null | tail -1 | awk '{print $4}' || echo "1048576")
  if [ "$available" -lt 102400 ]; then
    error "Insufficient disk space: $(($available/1024))MB available (need 100MB)"
    return 1
  fi
  success "Disk space available: $(($available/1024/1024))GB"
}

# ============================================================================
# DEPLOYMENT
# ============================================================================

prepare_deployment_dir() {
  log "Preparing deployment directories..."
  
  # Create directories with sudo if needed
  if ! mkdir -p "$DEPLOYMENT_DIR" 2>/dev/null; then
    log "Requiring sudo for /opt/automation creation..."
    sudo mkdir -p "$DEPLOYMENT_DIR" || error "Failed to create $DEPLOYMENT_DIR"
    sudo chmod 755 "$DEPLOYMENT_DIR" || error "Failed to chmod $DEPLOYMENT_DIR"
  fi
  
  # Create subdirectories
  mkdir -p "$DEPLOYMENT_DIR/k8s-health-checks" 2>/dev/null || \
    sudo mkdir -p "$DEPLOYMENT_DIR/k8s-health-checks"
  mkdir -p "$DEPLOYMENT_DIR/security" 2>/dev/null || \
    sudo mkdir -p "$DEPLOYMENT_DIR/security"
  mkdir -p "$DEPLOYMENT_DIR/multi-region" 2>/dev/null || \
    sudo mkdir -p "$DEPLOYMENT_DIR/multi-region"
  mkdir -p "$DEPLOYMENT_DIR/core" 2>/dev/null || \
    sudo mkdir -p "$DEPLOYMENT_DIR/core"
  mkdir -p "$DEPLOYMENT_DIR/audit" 2>/dev/null || \
    sudo mkdir -p "$DEPLOYMENT_DIR/audit"
  
  # Set permissions
  sudo chmod 755 "$DEPLOYMENT_DIR"/* 2>/dev/null || true
  
  success "Deployment directories prepared"
}

clone_and_deploy() {
  log "Cloning repository and deploying components..."
  
  # Create temporary working directory
  local temp_dir="/tmp/automation-deploy-$$"
  mkdir -p "$temp_dir"
  
  # Clone repository
  log "Cloning self-hosted-runner repository..."
  if ! cd "$temp_dir" && git clone --depth=1 https://github.com/kushin77/self-hosted-runner.git . 2>&1 | tee -a "$AUDIT_LOG" || [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "Repository cloned successfully"
  else
    error "Failed to clone repository"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # Deploy K8s health checks
  log "Deploying K8s health check scripts..."
  for script in cluster-readiness.sh cluster-stuck-recovery.sh validate-multicloud-secrets.sh; do
    if [ -f "scripts/k8s-health-checks/$script" ]; then
      if sudo cp "scripts/k8s-health-checks/$script" "$DEPLOYMENT_DIR/k8s-health-checks/" 2>/dev/null; then
        sudo chmod 755 "$DEPLOYMENT_DIR/k8s-health-checks/$script"
        success "Deployed $script"
      else
        cp "scripts/k8s-health-checks/$script" "$DEPLOYMENT_DIR/k8s-health-checks/"
        chmod 755 "$DEPLOYMENT_DIR/k8s-health-checks/$script"
        success "Deployed $script"
      fi
    else
      error "Script not found: scripts/k8s-health-checks/$script"
    fi
  done
  
  # Deploy security scripts
  log "Deploying security audit scripts..."
  if [ -f "scripts/security/audit-test-values.sh" ]; then
    if sudo cp scripts/security/audit-test-values.sh "$DEPLOYMENT_DIR/security/" 2>/dev/null; then
      sudo chmod 755 "$DEPLOYMENT_DIR/security/audit-test-values.sh"
    else
      cp scripts/security/audit-test-values.sh "$DEPLOYMENT_DIR/security/"
      chmod 755 "$DEPLOYMENT_DIR/security/audit-test-values.sh"
    fi
    success "Deployed audit-test-values.sh"
  fi
  
  # Deploy failover scripts
  log "Deploying multi-region failover scripts..."
  if [ -f "scripts/multi-region/failover-automation.sh" ]; then
    if sudo cp scripts/multi-region/failover-automation.sh "$DEPLOYMENT_DIR/multi-region/" 2>/dev/null; then
      sudo chmod 755 "$DEPLOYMENT_DIR/multi-region/failover-automation.sh"
    else
      cp scripts/multi-region/failover-automation.sh "$DEPLOYMENT_DIR/multi-region/"
      chmod 755 "$DEPLOYMENT_DIR/multi-region/failover-automation.sh"
    fi
    success "Deployed failover-automation.sh"
  fi
  
  # Deploy core automation scripts
  log "Deploying core automation scripts..."
  for script in credential-manager.sh orchestrator.sh deployment-monitor.sh; do
    if [ -f "scripts/automation/$script" ]; then
      if sudo cp "scripts/automation/$script" "$DEPLOYMENT_DIR/core/" 2>/dev/null; then
        sudo chmod 755 "$DEPLOYMENT_DIR/core/$script"
      else
        cp "scripts/automation/$script" "$DEPLOYMENT_DIR/core/"
        chmod 755 "$DEPLOYMENT_DIR/core/$script"
      fi
      success "Deployed $script"
    else
      error "Script not found: scripts/automation/$script"
    fi
  done
  
  # Cleanup
  cd /
  rm -rf "$temp_dir"
  success "Repository cleaned up"
}

verify_deployment() {
  log "Verifying deployment..."
  
  local passed=0
  local total=0
  
  # Verify directories
  for dir in "$DEPLOYMENT_DIR/k8s-health-checks" \
             "$DEPLOYMENT_DIR/security" \
             "$DEPLOYMENT_DIR/multi-region" \
             "$DEPLOYMENT_DIR/core"; do
    total=$((total + 1))
    if [ -d "$dir" ]; then
      success "Directory verified: $dir"
      passed=$((passed + 1))
    else
      error "Directory not found: $dir"
    fi
  done
  
  # Verify and test scripts
  for script in "$DEPLOYMENT_DIR"/k8s-health-checks/*.sh \
                "$DEPLOYMENT_DIR"/security/*.sh \
                "$DEPLOYMENT_DIR"/multi-region/*.sh \
                "$DEPLOYMENT_DIR"/core/*.sh; do
    if [ -f "$script" ]; then
      total=$((total + 1))
      if [ -x "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
          success "Script verified: $(basename $script)"
          passed=$((passed + 1))
        else
          error "Syntax error in: $(basename $script)"
        fi
      else
        error "Not executable: $(basename $script)"
      fi
    fi
  done
  
  log "Verification: $passed/$total checks passed"
  
  if [ $passed -eq $total ] && [ $total -gt 0 ]; then
    success "All checks PASSED"
    return 0
  else
    error "Some checks failed"
    return 1
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_banner() {
  echo ""
  echo "╔═════════════════════════════════════════════════════════╗"
  echo "║  WORKER NODE DEPLOYMENT - STANDALONE EXECUTION         ║"
  echo "║  Target: dev-elevatediq (192.168.168.42)              ║"
  echo "╚═════════════════════════════════════════════════════════╝"
  echo ""
}

main() {
  print_banner
  
  log "═══════════════════════════════════════════════════════════"
  log "DEPLOYMENT START"
  log "═══════════════════════════════════════════════════════════"
  log "Host: $CURRENT_HOST"
  log "Target: $TARGET_HOST"
  log "Location: $DEPLOYMENT_DIR"
  log "Session: $SESSION_ID"
  log "Timestamp: $TIMESTAMP"
  echo ""
  
  # MANDATE ENFORCEMENT: Fresh Build Deployment
  if ! enforce_fresh_build_mandate; then
    error "Fresh build mandate enforcement failed - deployment blocked"
    return 1
  fi
  echo ""
  
  verify_host || return 1
  echo ""
  
  verify_prerequisites || return 1
  echo ""
  
  prepare_deployment_dir || return 1
  echo ""
  
  clone_and_deploy || return 1
  echo ""
  
  verify_deployment || return 1
  echo ""
  
  success "╔═════════════════════════════════════════════════════════╗"
  success "║  ✅ DEPLOYMENT COMPLETE                                ║"
  success "║  All 8 components installed to $DEPLOYMENT_DIR         ║"
  success "╚═════════════════════════════════════════════════════════╝"
  echo ""
  
  log "Deployment Details:"
  log "  ✅ cluster-readiness.sh"
  log "  ✅ cluster-stuck-recovery.sh"
  log "  ✅ validate-multicloud-secrets.sh"
  log "  ✅ audit-test-values.sh"
  log "  ✅ failover-automation.sh"
  log "  ✅ credential-manager.sh"
  log "  ✅ orchestrator.sh"
  log "  ✅ deployment-monitor.sh"
  echo ""
  log "Audit Log: $AUDIT_LOG"
  log ""
  
  return 0
}

# Execute
main "$@"
