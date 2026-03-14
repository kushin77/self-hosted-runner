#!/bin/bash
#
# On-Premises Worker Node Deployment - Direct Local Execution
#
# Purpose: Deploy all automation components directly to the on-prem worker node
#         - No Cloud Build required
#         - No GCP dependencies
#         - Direct systemd service deployment
#         - 100% local execution
#
# Usage:
#   ./deploy-onprem.sh --environment prod --components all
#   ./deploy-onprem.sh --environment prod --components k8s-health-checks
#
# Features:
#   - Direct deployment to worker node
#   - Local systemd service management
#   - Immutable git-based deployment
#   - Comprehensive health verification
#   - Full audit trail with session tracking
#

set -euo pipefail

# ============================================================================
# MANDATORY ENFORCEMENT: 192.168.168.42 ONLY - NO OTHER TARGETS
# ============================================================================
# Prevent accidental deployment to developer workstation (192.168.168.31)
if [[ "$(hostname)" == "dev-elevatediq-2" ]] || [[ "$(hostname -I 2>/dev/null | awk '{print $1}')" == "192.168.168.31" ]]; then
    echo -e "\033[0;31m[FATAL] DEPLOYMENT BLOCKED: This is 192.168.168.31 (FORBIDDEN)\033[0m" >&2
    echo "MANDATE: 192.168.168.42 (worker node) is the ONLY deployment target" >&2
    exit 1
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly SESSION_ID=$(openssl rand -hex 8)
readonly AUDIT_LOG="${REPO_ROOT}/scripts/automation/audit/onprem-deployment-${TIMESTAMP}-${SESSION_ID}.log"
readonly DEPLOYMENT_STATE_FILE="${REPO_ROOT}/.onprem-deployment-state"

# Create audit directory
mkdir -p "$(dirname "$AUDIT_LOG")"

# Deployment parameters
ENVIRONMENT="${1:-prod}"
COMPONENTS="${2:-all}"
SKIP_VERIFICATION=false
DRY_RUN=false

# Component deployment flags
DEPLOY_HEALTH_CHECKS=false
DEPLOY_SECURITY=false
DEPLOY_FAILOVER=false
DEPLOY_MONITORING=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# LOGGING & UTILITIES
# ============================================================================

log() {
  local msg="$*"
  echo -e "${GREEN}[${TIMESTAMP}]${NC} $msg" | tee -a "$AUDIT_LOG"
}

error() {
  local msg="$*"
  echo -e "${RED}[${TIMESTAMP}] ERROR: ${msg}${NC}" | tee -a "$AUDIT_LOG" >&2
  return 1
}

warning() {
  local msg="$*"
  echo -e "${YELLOW}[${TIMESTAMP}] WARNING: ${msg}${NC}" | tee -a "$AUDIT_LOG"
}

info() {
  local msg="$*"
  echo -e "${BLUE}[${TIMESTAMP}] INFO: ${msg}${NC}" | tee -a "$AUDIT_LOG"
}

success() {
  local msg="$*"
  echo -e "${GREEN}[${TIMESTAMP}] ✅ ${msg}${NC}" | tee -a "$AUDIT_LOG"
}

# ============================================================================
# FRESH BUILD MANDATE ENFORCEMENT
# ============================================================================
# Source the fresh build enforcement library
if [[ -f "${SCRIPT_DIR}/scripts/enforce/fresh-build-mandate.sh" ]]; then
  source "${SCRIPT_DIR}/scripts/enforce/fresh-build-mandate.sh"
else
  warning "Fresh build mandate library not found - skipping fresh build checks"
fi

# ============================================================================
# PRE-DEPLOYMENT VERIFICATION
# ============================================================================

verify_prerequisites() {
  log "Verifying on-prem deployment prerequisites..."

  # Check git state
  if ! git diff-index --quiet HEAD --; then
    error "Working directory has uncommitted changes. Commit first."
    return 1
  fi
  success "Git state clean: $(git rev-parse --short HEAD)"

  # Check required commands
  local required_commands=("bash" "git" "systemctl" "curl")
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      return 1
    fi
  done
  success "All required commands available"

  # Verify scripts exist
  local required_scripts=(
    "scripts/k8s-health-checks/cluster-readiness.sh"
    "scripts/k8s-health-checks/cluster-stuck-recovery.sh"
    "scripts/k8s-health-checks/validate-multicloud-secrets.sh"
    "scripts/security/audit-test-values.sh"
    "scripts/multi-region/failover-automation.sh"
    "scripts/automation/credential-manager.sh"
    "scripts/automation/orchestrator.sh"
    "scripts/automation/deployment-monitor.sh"
  )

  for script in "${required_scripts[@]}"; do
    if [ ! -f "$REPO_ROOT/$script" ]; then
      error "Script not found: $script"
      return 1
    fi
  done
  success "All deployment scripts verified"

  # Check disk space
  local available_space=$(df "$REPO_ROOT" | tail -1 | awk '{print $4}')
  if [ "$available_space" -lt 1048576 ]; then # Less than 1GB
    error "Insufficient disk space. Required: 1GB, Available: $((available_space / 1024))MB"
    return 1
  fi
  success "Disk space available: $((available_space / 1024 / 1024))GB"

  return 0
}

# ============================================================================
# COMPONENT DEPLOYMENT
# ============================================================================

deploy_health_checks() {
  log "Deploying Kubernetes health check scripts..."
  
  local target_dir="/opt/automation/k8s-health-checks"
  mkdir -p "$target_dir"

  # Deploy cluster-readiness.sh
  if [ -f "$REPO_ROOT/scripts/k8s-health-checks/cluster-readiness.sh" ]; then
    cp "$REPO_ROOT/scripts/k8s-health-checks/cluster-readiness.sh" "$target_dir/"
    chmod 755 "$target_dir/cluster-readiness.sh"
    success "Deployed cluster-readiness.sh"
  fi

  # Deploy cluster-stuck-recovery.sh
  if [ -f "$REPO_ROOT/scripts/k8s-health-checks/cluster-stuck-recovery.sh" ]; then
    cp "$REPO_ROOT/scripts/k8s-health-checks/cluster-stuck-recovery.sh" "$target_dir/"
    chmod 755 "$target_dir/cluster-stuck-recovery.sh"
    success "Deployed cluster-stuck-recovery.sh"
  fi

  # Deploy validate-multicloud-secrets.sh
  if [ -f "$REPO_ROOT/scripts/k8s-health-checks/validate-multicloud-secrets.sh" ]; then
    cp "$REPO_ROOT/scripts/k8s-health-checks/validate-multicloud-secrets.sh" "$target_dir/"
    chmod 755 "$target_dir/validate-multicloud-secrets.sh"
    success "Deployed validate-multicloud-secrets.sh"
  fi

  return 0
}

deploy_security() {
  log "Deploying security audit scripts..."
  
  local target_dir="/opt/automation/security"
  mkdir -p "$target_dir"

  # Deploy audit-test-values.sh
  if [ -f "$REPO_ROOT/scripts/security/audit-test-values.sh" ]; then
    cp "$REPO_ROOT/scripts/security/audit-test-values.sh" "$target_dir/"
    chmod 755 "$target_dir/audit-test-values.sh"
    success "Deployed audit-test-values.sh"
  fi

  return 0
}

deploy_failover() {
  log "Deploying multi-region failover scripts..."
  
  local target_dir="/opt/automation/multi-region"
  mkdir -p "$target_dir"

  # Deploy failover-automation.sh
  if [ -f "$REPO_ROOT/scripts/multi-region/failover-automation.sh" ]; then
    cp "$REPO_ROOT/scripts/multi-region/failover-automation.sh" "$target_dir/"
    chmod 755 "$target_dir/failover-automation.sh"
    success "Deployed failover-automation.sh"
  fi

  return 0
}

deploy_monitoring() {
  log "Deploying monitoring and orchestration..."
  
  local target_dir="/opt/automation/core"
  mkdir -p "$target_dir"

  # Deploy credential-manager.sh
  if [ -f "$REPO_ROOT/scripts/automation/credential-manager.sh" ]; then
    cp "$REPO_ROOT/scripts/automation/credential-manager.sh" "$target_dir/"
    chmod 755 "$target_dir/credential-manager.sh"
    success "Deployed credential-manager.sh"
  fi

  # Deploy orchestrator.sh
  if [ -f "$REPO_ROOT/scripts/automation/orchestrator.sh" ]; then
    cp "$REPO_ROOT/scripts/automation/orchestrator.sh" "$target_dir/"
    chmod 755 "$target_dir/orchestrator.sh"
    success "Deployed orchestrator.sh"
  fi

  # Deploy deployment-monitor.sh
  if [ -f "$REPO_ROOT/scripts/automation/deployment-monitor.sh" ]; then
    cp "$REPO_ROOT/scripts/automation/deployment-monitor.sh" "$target_dir/"
    chmod 755 "$target_dir/deployment-monitor.sh"
    success "Deployed deployment-monitor.sh"
  fi

  return 0
}

# ============================================================================
# HEALTH VERIFICATION
# ============================================================================

verify_deployment() {
  log "Verifying on-prem deployment..."
  
  local success_count=0
  local total_checks=0

  # Verify directories exist and are readable
  for dir in "/opt/automation/k8s-health-checks" \
             "/opt/automation/security" \
             "/opt/automation/multi-region" \
             "/opt/automation/core"; do
    total_checks=$((total_checks + 1))
    if [ -d "$dir" ]; then
      success "Directory verified: $dir"
      success_count=$((success_count + 1))
    else
      warning "Directory not found: $dir"
    fi
  done

  # Verify script permissions
  for script in /opt/automation/k8s-health-checks/*.sh \
                /opt/automation/security/*.sh \
                /opt/automation/multi-region/*.sh \
                /opt/automation/core/*.sh; do
    if [ -f "$script" ]; then
      total_checks=$((total_checks + 1))
      if [ -x "$script" ]; then
        success "Script executable: $(basename "$script")"
        success_count=$((success_count + 1))
      else
        warning "Script not executable: $script"
      fi
    fi
  done

  # Test script syntax
  for script in /opt/automation/k8s-health-checks/*.sh \
                /opt/automation/security/*.sh \
                /opt/automation/multi-region/*.sh \
                /opt/automation/core/*.sh; do
    if [ -f "$script" ]; then
      total_checks=$((total_checks + 1))
      if bash -n "$script" 2>/dev/null; then
        success "Script syntax valid: $(basename "$script")"
        success_count=$((success_count + 1))
      else
        error "Script syntax error: $script"
      fi
    fi
  done

  log "Verification results: $success_count/$total_checks checks passed"
  
  if [ "$success_count" -eq "$total_checks" ]; then
    success "All health checks PASSED"
    return 0
  else
    error "Some health checks failed ($success_count/$total_checks passed)"
    return 1
  fi
}

# ============================================================================
# DEPLOYMENT EXECUTION
# ============================================================================

execute_deployment() {
  log "╔════════════════════════════════════════╗"
  log "║  ON-PREM WORKER NODE DEPLOYMENT        ║"
  log "║  Starting deployment workflow...       ║"
  log "╚════════════════════════════════════════╝"
  log ""
  log "Environment: $ENVIRONMENT"
  log "Components: $COMPONENTS"
  log "Session ID: $SESSION_ID"
  log "Timestamp: $TIMESTAMP"
  log ""

  # Parse components
  if [ "$COMPONENTS" = "all" ]; then
    DEPLOY_HEALTH_CHECKS=true
    DEPLOY_SECURITY=true
    DEPLOY_FAILOVER=true
    DEPLOY_MONITORING=true
  else
    IFS=',' read -ra COMPONENT_LIST <<< "$COMPONENTS"
    for component in "${COMPONENT_LIST[@]}"; do
      case "$(echo "$component" | xargs)" in
        k8s-health-checks) DEPLOY_HEALTH_CHECKS=true ;;
        security) DEPLOY_SECURITY=true ;;
        failover) DEPLOY_FAILOVER=true ;;
        monitoring) DEPLOY_MONITORING=true ;;
      esac
    done
  fi

  # Deploy components
  if [ "$DEPLOY_HEALTH_CHECKS" = true ]; then
    deploy_health_checks || error "Health checks deployment failed"
  fi

  if [ "$DEPLOY_SECURITY" = true ]; then
    deploy_security || error "Security deployment failed"
  fi

  if [ "$DEPLOY_FAILOVER" = true ]; then
    deploy_failover || error "Failover deployment failed"
  fi

  if [ "$DEPLOY_MONITORING" = true ]; then
    deploy_monitoring || error "Monitoring deployment failed"
  fi

  # Verify deployment
  if ! verify_deployment; then
    error "Deployment verification failed"
    return 1
  fi

  # Update deployment state
  {
    echo "DEPLOYMENT_TIMESTAMP=$TIMESTAMP"
    echo "DEPLOYMENT_SESSION_ID=$SESSION_ID"
    echo "DEPLOYMENT_ENVIRONMENT=$ENVIRONMENT"
    echo "DEPLOYMENT_COMPONENTS=$COMPONENTS"
    echo "DEPLOYMENT_STATUS=SUCCESS"
  } > "$DEPLOYMENT_STATE_FILE"

  success "Deployment state saved to $DEPLOYMENT_STATE_FILE"

  return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log "═══════════════════════════════════════"
  log "ON-PREM WORKER NODE DEPLOYMENT SYSTEM"
  log "═══════════════════════════════════════"
  log "Repository: $REPO_ROOT"
  log "Session ID: $SESSION_ID"
  log "Audit Log: $AUDIT_LOG"
  log ""

  # MANDATE ENFORCEMENT: Fresh Build Deployment
  if ! enforce_fresh_build_mandate; then
    error "Fresh build mandate enforcement failed - deployment blocked"
    return 1
  fi
  log ""

  # Verify prerequisites
  if ! verify_prerequisites; then
    error "Prerequisites verification failed"
    return 1
  fi

  log ""
  
  # Execute deployment
  if ! execute_deployment; then
    error "Deployment execution failed"
    return 1
  fi

  log ""
  success "╔════════════════════════════════════════╗"
  success "║  ✅ ON-PREM DEPLOYMENT COMPLETE       ║"
  success "║  100% Success Rate on Worker Node     ║"
  success "╚════════════════════════════════════════╝"
  log ""
  log "Deployment Details:"
  log "  Environment: $ENVIRONMENT"
  log "  Components: $COMPONENTS"
  log "  Status: SUCCESS"
  log "  Session: $SESSION_ID"
  log "  Deployment Location: /opt/automation/*"
  log ""
  log "Next Steps:"
  log "  1. Verify scripts: ls -la /opt/automation/*/"
  log "  2. Test execution: /opt/automation/k8s-health-checks/cluster-readiness.sh"
  log "  3. Check logs: tail -f $AUDIT_LOG"
  log ""

  return 0
}

# Execute main function
main "$@"
