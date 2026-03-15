#!/bin/bash
#
# Phase 3 Deployment Executor (Service Account Wrapper)
# Ensures deployment runs as 'automation' service account without sudo
#
# Usage: bash scripts/redeploy/phase3-deployment-exec.sh [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVICE_ACCOUNT="automation"
DEPLOYMENT_SCRIPT="$REPO_DIR/scripts/redeploy/phase3-deployment-trigger.sh"
DRY_RUN="${DRY_RUN:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }

check_current_user() {
  local current_user="$(whoami)"
  
  if [[ "$current_user" == "$SERVICE_ACCOUNT" ]]; then
    log_success "Running as service account: $SERVICE_ACCOUNT"
    return 0
  elif [[ "$current_user" == "root" ]]; then
    log_error "Cannot run as root (sudo). Use service account '$SERVICE_ACCOUNT' instead."
    log_info "Execute as: su - $SERVICE_ACCOUNT -c 'bash $DEPLOYMENT_SCRIPT'"
    return 1
  else
    log_warn "Running as '$current_user' (not '$SERVICE_ACCOUNT')"
    log_info "For production, execute as: su - $SERVICE_ACCOUNT -c 'bash $DEPLOYMENT_SCRIPT'"
    return 0
  fi
}

check_service_account_exists() {
  if id "$SERVICE_ACCOUNT" &>/dev/null; then
    log_success "Service account '$SERVICE_ACCOUNT' exists"
    return 0
  else
    log_error "Service account '$SERVICE_ACCOUNT' does not exist"
    log_info "Create with: sudo useradd -r -s /bin/bash -d /home/$SERVICE_ACCOUNT $SERVICE_ACCOUNT"
    return 1
  fi
}

verify_script_exists() {
  if [[ -f "$DEPLOYMENT_SCRIPT" ]]; then
    log_success "Deployment script found: $DEPLOYMENT_SCRIPT"
    return 0
  else
    log_error "Deployment script not found: $DEPLOYMENT_SCRIPT"
    return 1
  fi
}

execute_as_service_account() {
  local current_user="$(whoami)"
  
  if [[ "$current_user" == "$SERVICE_ACCOUNT" ]]; then
    # Already running as service account - execute directly
    log_info "Executing as $SERVICE_ACCOUNT (direct)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY-RUN] Would execute: bash $DEPLOYMENT_SCRIPT"
      return 0
    fi
    
    bash "$DEPLOYMENT_SCRIPT"
    return $?
  else
    # Need to switch user - use su
    log_info "Switching to service account: $SERVICE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY-RUN] Would execute: su - $SERVICE_ACCOUNT -c 'bash $DEPLOYMENT_SCRIPT'"
      return 0
    fi
    
    # Use su to switch to service account (no sudo)
    su - "$SERVICE_ACCOUNT" -c "bash $DEPLOYMENT_SCRIPT"
    return $?
  fi
}

main() {
  log_info "Phase 3 Deployment Executor (Service Account Wrapper)"
  log_info "Service Account: $SERVICE_ACCOUNT"
  log_info "Deployment Script: $DEPLOYMENT_SCRIPT"
  
  # Verify prerequisites
  verify_script_exists || return 1
  check_service_account_exists || return 1
  check_current_user || return 1
  
  log_info ""
  log_info "Executing Phase 3 deployment..."
  log_info ""
  
  # Execute as service account
  execute_as_service_account
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    log_success "Phase 3 deployment completed successfully"
  else
    log_error "Phase 3 deployment failed with exit code $exit_code"
  fi
  
  return $exit_code
}

main "$@"
