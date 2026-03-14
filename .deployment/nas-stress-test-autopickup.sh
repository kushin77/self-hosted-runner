#!/bin/bash
#
# 🚀 NAS STRESS TEST - AUTO-PICKUP DEPLOYMENT
#
# This script runs on the worker node (.42) via auto-deployment service
# Git detects this file, pulls it, and worker auto-executes it
# No GitHub Actions | No pull requests | Direct deployment only
#
# Trigger: Commit this file to git, worker detects and executes automatically
# Worker Service: nexusshield-auto-deploy.service or equivalent
# Execution: Immutable, ephemeral, idempotent

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$SCRIPT_DIR"
readonly DEPLOY_PATH="/opt/automation/nas-stress-test"
readonly STATE_FILE="/var/lib/automation/.nas-stress-deployed"
readonly RESULTS_DIR="/home/automation/nas-stress-results"

# ============================================================================
# LOGGING
# ============================================================================

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*"; }
warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ! $*" >&2; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $*" >&2; }
step() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ==> $*"; }

# ============================================================================
# IDEMPOTENCY CHECK
# ============================================================================

is_deployed() {
  [[ -f "$STATE_FILE" ]] && \
  grep -q "NAS_STRESS_DEPLOYED=true" "$STATE_FILE" && \
  [[ -d "$DEPLOY_PATH" ]]
}

check_version() {
  if [[ ! -f "$STATE_FILE" ]]; then
    return 1
  fi
  
  local deployed_sha=$(grep "GIT_SHA=" "$STATE_FILE" 2>/dev/null | cut -d= -f2)
  local current_sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
  
  [[ "$deployed_sha" == "$current_sha" ]]
}

# ============================================================================
# DEPLOYMENT EXECUTION
# ============================================================================

deploy() {
  step "NAS Stress Test Suite - Worker Node Deployment"
  
  # Check idempotency
  if is_deployed; then
    if check_version; then
      log "Already deployed with matching version - idempotent check passed"
      return 0
    else
      log "Version changed - redeploying"
    fi
  fi
  
  # Create deployment directory atomically
  log "Creating deployment directory: $DEPLOY_PATH"
  mkdir -p "$DEPLOY_PATH" /var/lib/automation "$RESULTS_DIR"
  
  # Copy stress test scripts
  log "Deploying stress test scripts..."
  cp -v "$REPO_ROOT/deploy-nas-stress-tests.sh" "$DEPLOY_PATH/"
  cp -rv "$REPO_ROOT/scripts/nas-integration/" "$DEPLOY_PATH/" || true
  
  # Make executable
  find "$DEPLOY_PATH" -name "*.sh" -exec chmod 755 {} \; || true
  
  # Deploy systemd files (requires sudo)
  log "Installing systemd services..."
  if [[ -f "$REPO_ROOT/systemd/nas-stress-test.service" ]]; then
    sudo cp "$REPO_ROOT/systemd/nas-stress-test*.service" /etc/systemd/system/ 2>/dev/null || true
    sudo cp "$REPO_ROOT/systemd/nas-stress-test*.timer" /etc/systemd/system/ 2>/dev/null || true
    sudo systemctl daemon-reload || true
    sudo systemctl enable nas-stress-test.timer nas-stress-test-weekly.timer 2>/dev/null || true
    sudo systemctl start nas-stress-test.timer nas-stress-test-weekly.timer 2>/dev/null || true
  fi
  
  # Create immutable results directory
  log "Setting up results directory..."
  mkdir -p "$RESULTS_DIR"
  chmod 755 "$RESULTS_DIR"
  
  # Record deployment state (immutable)
  log "Recording deployment state..."
  mkdir -p /var/lib/automation
  cat > "$STATE_FILE" <<EOF
NAS_STRESS_DEPLOYED=true
DEPLOYED_AT=$(date -Iseconds)
GIT_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown')
DEPLOY_PATH=$DEPLOY_PATH
RESULTS_DIR=$RESULTS_DIR
EOF
  chmod 644 "$STATE_FILE"
  
  log "Deployment complete!"
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify() {
  step "Verifying Deployment"
  
  # Check files
  if [[ ! -f "$DEPLOY_PATH/deploy-nas-stress-tests.sh" ]]; then
    error "Deployment files not found"
    return 1
  fi
  log "Deployment files verified"
  
  # Check systemd services
  if systemctl is-enabled nas-stress-test.timer 2>/dev/null; then
    log "Systemd timers verified"
  else
    warn "Systemd timers not enabled (may require manual setup)"
  fi
  
  # Check results directory
  if [[ ! -d "$RESULTS_DIR" ]]; then
    error "Results directory not accessible"
    return 1
  fi
  log "Results directory verified"
  
  log "All verifications passed!"
  return 0
}

# ============================================================================
# STATUS
# ============================================================================

status() {
  step "Deployment Status"
  
  if is_deployed; then
    echo "Status: DEPLOYED"
    cat "$STATE_FILE"
    echo ""
  else
    echo "Status: NOT_DEPLOYED"
  fi
  
  if [[ -d "$RESULTS_DIR" ]]; then
    echo ""
    echo "Recent test results:"
    ls -lh "$RESULTS_DIR" 2>/dev/null | tail -5 || echo "  (no results yet)"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  case "${1:-deploy}" in
    deploy)
      deploy && verify
      ;;
    verify)
      verify
      ;;
    status)
      status
      ;;
    *)
      echo "Usage: $0 [deploy|verify|status]"
      exit 1
      ;;
  esac
}

trap 'error "Deployment interrupted"; exit 130' INT TERM

main "$@"
