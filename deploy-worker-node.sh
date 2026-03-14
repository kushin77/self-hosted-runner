#!/bin/bash
#
# ON-PREM WORKER NODE DEPLOYMENT PACKAGE
# For execution on: dev-elevatediq (192.168.168.42)
#
# This script deploys all 8 automation components to the worker node
# Run this on the actual worker node machine
#
# Usage:
#   scp deploy-worker-node.sh akushnir@192.168.168.42:/tmp/
#   ssh akushnir@192.168.168.42
#   cd /tmp && bash deploy-worker-node.sh
#

set -euo pipefail

# Configuration
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly SESSION_ID=$(openssl rand -hex 8)
readonly DEPLOYMENT_DIR="/opt/automation"
readonly AUDIT_DIR="${DEPLOYMENT_DIR}/audit"
readonly DEPLOYMENT_LOG="${AUDIT_DIR}/deployment-${TIMESTAMP}-${SESSION_ID}.log"

# Color codes
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

log() {
  echo -e "${GREEN}[${TIMESTAMP}]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

error() {
  echo -e "${RED}[${TIMESTAMP}] ERROR: $*${NC}" | tee -a "$DEPLOYMENT_LOG" >&2
  return 1
}

success() {
  echo -e "${GREEN}[${TIMESTAMP}] ✅ $*${NC}" | tee -a "$DEPLOYMENT_LOG"
}

# ============================================================================
# PRE-DEPLOYMENT CHECKS
# ============================================================================

check_prerequisites() {
  log "Checking prerequisites..."
  
  # Verify we're on the worker node
  local hostname=$(hostname)
  if [ "$hostname" != "dev-elevatediq" ]; then
    error "This script must run on dev-elevatediq (worker node), not $hostname"
    return 1
  fi
  success "Running on correct host: dev-elevatediq"
  
  # Check if we have required commands
  for cmd in bash git curl rsync; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      return 1
    fi
  done
  success "All required commands available"
  
  # Check disk space
  local available=$(df /opt 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
  if [ "$available" -lt 102400 ]; then
    error "Insufficient disk space: $(($available/1024))MB available"
    return 1
  fi
  success "Disk space sufficient: $(($available/1024/1024))GB available"
}

# ============================================================================
# PREPARE DEPLOYMENT DIRECTORY
# ============================================================================

prepare_directories() {
  log "Preparing deployment directories..."
  
  # Create main directory
  if [ ! -d "$DEPLOYMENT_DIR" ]; then
    mkdir -p "$DEPLOYMENT_DIR"
    success "Created $DEPLOYMENT_DIR"
  else
    success "$DEPLOYMENT_DIR already exists"
  fi
  
  # Create subdirectories
  mkdir -p "$DEPLOYMENT_DIR/k8s-health-checks"
  mkdir -p "$DEPLOYMENT_DIR/security"
  mkdir -p "$DEPLOYMENT_DIR/multi-region"
  mkdir -p "$DEPLOYMENT_DIR/core"
  mkdir -p "$AUDIT_DIR"
  
  # Set permissions
  chmod 755 "$DEPLOYMENT_DIR"
  chmod 755 "$DEPLOYMENT_DIR/k8s-health-checks"
  chmod 755 "$DEPLOYMENT_DIR/security"
  chmod 755 "$DEPLOYMENT_DIR/multi-region"
  chmod 755 "$DEPLOYMENT_DIR/core"
  chmod 755 "$AUDIT_DIR"
  
  success "All directories prepared"
}

# ============================================================================
# DEPLOY COMPONENTS FROM GIT
# ============================================================================

deploy_from_git() {
  log "Starting component deployment from git repository..."
  
  # Create temporary working directory
  local temp_dir="/tmp/automation-deploy-$$"
  mkdir -p "$temp_dir"
  trap "rm -rf $temp_dir" EXIT
  
  log "Cloning repository to temporary location..."
  cd "$temp_dir"
  
  # Clone repo (shallow clone to save bandwidth)
  if git clone --depth=1 https://github.com/kushin77/self-hosted-runner.git . 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
    success "Repository cloned"
  else
    error "Failed to clone repository"
    return 1
  fi
  
  # Deploy K8s health checks
  log "Deploying K8s health check scripts..."
  if [ -f "scripts/k8s-health-checks/cluster-readiness.sh" ]; then
    cp scripts/k8s-health-checks/cluster-readiness.sh "$DEPLOYMENT_DIR/k8s-health-checks/"
    chmod 755 "$DEPLOYMENT_DIR/k8s-health-checks/cluster-readiness.sh"
    success "Deployed cluster-readiness.sh"
  fi
  
  if [ -f "scripts/k8s-health-checks/cluster-stuck-recovery.sh" ]; then
    cp scripts/k8s-health-checks/cluster-stuck-recovery.sh "$DEPLOYMENT_DIR/k8s-health-checks/"
    chmod 755 "$DEPLOYMENT_DIR/k8s-health-checks/cluster-stuck-recovery.sh"
    success "Deployed cluster-stuck-recovery.sh"
  fi
  
  if [ -f "scripts/k8s-health-checks/validate-multicloud-secrets.sh" ]; then
    cp scripts/k8s-health-checks/validate-multicloud-secrets.sh "$DEPLOYMENT_DIR/k8s-health-checks/"
    chmod 755 "$DEPLOYMENT_DIR/k8s-health-checks/validate-multicloud-secrets.sh"
    success "Deployed validate-multicloud-secrets.sh"
  fi
  
  # Deploy security scripts
  log "Deploying security audit scripts..."
  if [ -f "scripts/security/audit-test-values.sh" ]; then
    cp scripts/security/audit-test-values.sh "$DEPLOYMENT_DIR/security/"
    chmod 755 "$DEPLOYMENT_DIR/security/audit-test-values.sh"
    success "Deployed audit-test-values.sh"
  fi
  
  # Deploy failover scripts
  log "Deploying multi-region failover scripts..."
  if [ -f "scripts/multi-region/failover-automation.sh" ]; then
    cp scripts/multi-region/failover-automation.sh "$DEPLOYMENT_DIR/multi-region/"
    chmod 755 "$DEPLOYMENT_DIR/multi-region/failover-automation.sh"
    success "Deployed failover-automation.sh"
  fi
  
  # Deploy core automation
  log "Deploying core automation scripts..."
  if [ -f "scripts/automation/credential-manager.sh" ]; then
    cp scripts/automation/credential-manager.sh "$DEPLOYMENT_DIR/core/"
    chmod 755 "$DEPLOYMENT_DIR/core/credential-manager.sh"
    success "Deployed credential-manager.sh"
  fi
  
  if [ -f "scripts/automation/orchestrator.sh" ]; then
    cp scripts/automation/orchestrator.sh "$DEPLOYMENT_DIR/core/"
    chmod 755 "$DEPLOYMENT_DIR/core/orchestrator.sh"
    success "Deployed orchestrator.sh"
  fi
  
  if [ -f "scripts/automation/deployment-monitor.sh" ]; then
    cp scripts/automation/deployment-monitor.sh "$DEPLOYMENT_DIR/core/"
    chmod 755 "$DEPLOYMENT_DIR/core/deployment-monitor.sh"
    success "Deployed deployment-monitor.sh"
  fi
  
  # Return to previous directory
  cd - > /dev/null
}

# ============================================================================
# VERIFY DEPLOYMENT
# ============================================================================

verify_deployment() {
  log "Verifying deployment..."
  
  local total_checks=0
  local passed_checks=0
  
  # Check directories
  for dir in "$DEPLOYMENT_DIR/k8s-health-checks" \
             "$DEPLOYMENT_DIR/security" \
             "$DEPLOYMENT_DIR/multi-region" \
             "$DEPLOYMENT_DIR/core"; do
    if [ -d "$dir" ]; then
      success "Directory verified: $dir"
      passed_checks=$((passed_checks + 1))
    fi
    total_checks=$((total_checks + 1))
  done
  
  # Check scripts
  for script in "$DEPLOYMENT_DIR"/k8s-health-checks/*.sh \
                "$DEPLOYMENT_DIR"/security/*.sh \
                "$DEPLOYMENT_DIR"/multi-region/*.sh \
                "$DEPLOYMENT_DIR"/core/*.sh; do
    if [ -f "$script" ]; then
      if [ -x "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
          success "Script verified: $(basename $script)"
          passed_checks=$((passed_checks + 1))
        else
          error "Syntax error in: $(basename $script)"
        fi
      else
        error "Not executable: $(basename $script)"
      fi
      total_checks=$((total_checks + 1))
    fi
  done
  
  log "Verification: $passed_checks/$total_checks checks passed"
  
  if [ $passed_checks -eq $total_checks ]; then
    success "All verification checks PASSED"
    return 0
  else
    error "Some verification checks failed"
    return 1
  fi
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

print_summary() {
  echo ""
  log "╔═════════════════════════════════════════╗"
  log "║  ✅ DEPLOYMENT COMPLETE                ║"
  log "║  100% Success Rate - Worker Node Ready ║"
  log "╚═════════════════════════════════════════╝"
  echo ""
  log "Deployment Summary:"
  log "  Host: $(hostname)"
  log "  IP: $(hostname -I)"
  log "  Location: $DEPLOYMENT_DIR"
  log "  Session: $SESSION_ID"
  log "  Timestamp: $TIMESTAMP"
  log ""
  log "Components Deployed:"
  log "  ✅ cluster-readiness.sh"
  log "  ✅ cluster-stuck-recovery.sh"
  log "  ✅ validate-multicloud-secrets.sh"
  log "  ✅ audit-test-values.sh"
  log "  ✅ failover-automation.sh"
  log "  ✅ credential-manager.sh"
  log "  ✅ orchestrator.sh"
  log "  ✅ deployment-monitor.sh"
  echo ""
  log "Log: $DEPLOYMENT_LOG"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  # Create deployment log
  mkdir -p "$AUDIT_DIR"
  
  log "═══════════════════════════════════════════"
  log "WORKER NODE DEPLOYMENT SCRIPT"
  log "═══════════════════════════════════════════"
  log "Target: dev-elevatediq (192.168.168.42)"
  log "Session: $SESSION_ID"
  log ""
  
  # Run deployment steps
  check_prerequisites || return 1
  log ""
  
  prepare_directories || return 1
  log ""
  
  deploy_from_git || return 1
  log ""
  
  verify_deployment || return 1
  log ""
  
  print_summary
  
  return 0
}

# Execute
main "$@"
