#!/bin/bash
#
# WORKER NODE DEPLOYMENT - SERVICE ACCOUNT SSH AUTH
# For: dev-elevatediq (192.168.168.42)
#
# Deploys all 8 automation components via SSH service account authentication
# Run this on your developer machine
#
# Prerequisites:
#   - Service account SSH key configured
#   - SSH access to 192.168.168.42
#
# Usage:
#   # Option 1: Using default service account (automation)
#   bash deploy-worker-node.sh
#
#   # Option 2: Using specific service account
#   SERVICE_ACCOUNT=github-actions bash deploy-worker-node.sh
#
#   # Option 3: Using specific SSH key
#   SSH_KEY=/path/to/private/key bash deploy-worker-node.sh
#
#   # Option 4: Using different target host
#   TARGET_HOST=192.168.168.42 SERVICE_ACCOUNT=automation bash deploy-worker-node.sh
#

set -euo pipefail

# ============================================================================
# SSH SERVICE ACCOUNT CONFIGURATION
# ============================================================================

# Service account credentials
readonly SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-automation}"
readonly TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
readonly TARGET_USER="${TARGET_USER:-$SERVICE_ACCOUNT}"
readonly SSH_KEY="${SSH_KEY:-}"

# SSH connection options
readonly SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Detect SSH key location
detect_ssh_key() {
  if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
    echo "$SSH_KEY"
    return 0
  fi
  
  # Try common service account key locations
  for key_path in \
    ~/.ssh/id_${SERVICE_ACCOUNT} \
    ~/.ssh/${SERVICE_ACCOUNT}_rsa \
    ~/.ssh/service-accounts/${SERVICE_ACCOUNT} \
    ~/.ssh/service-accounts/${SERVICE_ACCOUNT}_rsa \
    ~/.ssh/github-actions \
    ~/.ssh/automation \
    ~/.ssh/id_rsa; do
    if [ -f "$key_path" ]; then
      echo "$key_path"
      return 0
    fi
  done
  
  return 1
}

# Verify SSH connectivity before deployment
verify_ssh_connection() {
  local ssh_key="$1"
  local ssh_cmd="ssh -i \"$ssh_key\" $SSH_OPTS"
  
  echo "Verifying SSH connection to $TARGET_USER@$TARGET_HOST..."
  if $ssh_cmd "$TARGET_USER@$TARGET_HOST" echo "SSH connection successful"; then
    echo "✅ SSH connection verified"
    return 0
  else
    echo "❌ SSH connection failed"
    return 1
  fi
}

# Deployment configuration
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

# ============================================================================
# PRE-DEPLOYMENT CHECKS
# ============================================================================

check_prerequisites() {
  log "Checking prerequisites for remote deployment..."
  
  # Check SSH key availability
  if ! SSH_KEY_PATH=$(detect_ssh_key); then
    error "No SSH key found for service account '$SERVICE_ACCOUNT'"
    error "Tried locations:"
    error "  ~/.ssh/id_${SERVICE_ACCOUNT}"
    error "  ~/.ssh/${SERVICE_ACCOUNT}_rsa"
    error "  ~/.ssh/service-accounts/${SERVICE_ACCOUNT}"
    error "  ~/.ssh/github-actions"
    error "  ~/.ssh/id_rsa"
    return 1
  fi
  success "Found SSH key: $SSH_KEY_PATH"
  
  # Verify SSH connection to worker node
  if ! verify_ssh_connection "$SSH_KEY_PATH"; then
    error "Cannot connect to $TARGET_USER@$TARGET_HOST"
    error "Please verify:"
    error "  1. Worker node is reachable at $TARGET_HOST"
    error "  2. Service account '$SERVICE_ACCOUNT' exists on worker node"
    error "  3. SSH key is authorized on worker node"
    return 1
  fi
  success "SSH connection verified"
  
  # Check for required commands on local machine
  for cmd in bash ssh scp; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found locally: $cmd"
      return 1
    fi
  done
  success "All required local commands available"
  
  success "All prerequisites verified"
}

# ============================================================================
# REMOTE EXECUTION HELPERS
# ============================================================================

execute_remote() {
  local ssh_key="$1"
  shift
  local cmd="$@"
  
  ssh -i "$ssh_key" $SSH_OPTS "$TARGET_USER@$TARGET_HOST" bash -c "$cmd"
}

copy_to_remote() {
  local ssh_key="$1"
  local local_file="$2"
  local remote_path="$3"
  
  scp -i "$ssh_key" $SSH_OPTS "$local_file" "$TARGET_USER@$TARGET_HOST:$remote_path"
}

# ============================================================================
# PREPARE DEPLOYMENT DIRECTORY
# ============================================================================

prepare_directories() {
  local ssh_key="$1"
  log "Preparing remote deployment directories..."
  
  local cmd="
    mkdir -p $DEPLOYMENT_DIR/k8s-health-checks
    mkdir -p $DEPLOYMENT_DIR/security
    mkdir -p $DEPLOYMENT_DIR/multi-region
    mkdir -p $DEPLOYMENT_DIR/core
    mkdir -p $AUDIT_DIR
    chmod 755 $DEPLOYMENT_DIR
    chmod 755 $DEPLOYMENT_DIR/k8s-health-checks
    chmod 755 $DEPLOYMENT_DIR/security
    chmod 755 $DEPLOYMENT_DIR/multi-region
    chmod 755 $DEPLOYMENT_DIR/core
    chmod 755 $AUDIT_DIR
    echo 'Directories prepared on remote host'
  "
  
  if execute_remote "$ssh_key" "$cmd"; then
    success "Remote directories prepared"
  else
    error "Failed to prepare remote directories"
    return 1
  fi
}

# ============================================================================
# DEPLOY COMPONENTS FROM GIT
# ============================================================================

deploy_from_git() {
  local ssh_key="$1"
  log "Starting remote component deployment from git repository..."
  
  local cmd="
    set -euo pipefail
    TEMP_DIR=\$(mktemp -d)
    trap 'rm -rf \$TEMP_DIR' EXIT
    
    echo 'Cloning repository...'
    cd \$TEMP_DIR
    git clone --depth=1 https://github.com/kushin77/self-hosted-runner.git . 2>&1
    
    echo 'Deploying K8s health checks...'
    cp scripts/k8s-health-checks/cluster-readiness.sh $DEPLOYMENT_DIR/k8s-health-checks/ && chmod 755 $DEPLOYMENT_DIR/k8s-health-checks/cluster-readiness.sh
    cp scripts/k8s-health-checks/cluster-stuck-recovery.sh $DEPLOYMENT_DIR/k8s-health-checks/ && chmod 755 $DEPLOYMENT_DIR/k8s-health-checks/cluster-stuck-recovery.sh
    cp scripts/k8s-health-checks/validate-multicloud-secrets.sh $DEPLOYMENT_DIR/k8s-health-checks/ && chmod 755 $DEPLOYMENT_DIR/k8s-health-checks/validate-multicloud-secrets.sh
    
    echo 'Deploying security scripts...'
    cp scripts/security/audit-test-values.sh $DEPLOYMENT_DIR/security/ && chmod 755 $DEPLOYMENT_DIR/security/audit-test-values.sh
    
    echo 'Deploying multi-region failover...'
    cp scripts/multi-region/failover-automation.sh $DEPLOYMENT_DIR/multi-region/ && chmod 755 $DEPLOYMENT_DIR/multi-region/failover-automation.sh
    
    echo 'Deploying core automation...'
    cp scripts/automation/credential-manager.sh $DEPLOYMENT_DIR/core/ && chmod 755 $DEPLOYMENT_DIR/core/credential-manager.sh
    cp scripts/automation/orchestrator.sh $DEPLOYMENT_DIR/core/ && chmod 755 $DEPLOYMENT_DIR/core/orchestrator.sh
    cp scripts/automation/deployment-monitor.sh $DEPLOYMENT_DIR/core/ && chmod 755 $DEPLOYMENT_DIR/core/deployment-monitor.sh
    
    echo 'Deployment complete'
  "
  
  if execute_remote "$ssh_key" "$cmd"; then
    success "Remote components deployed successfully"
  else
    error "Failed to deploy remote components"
    return 1
  fi
}

# ============================================================================
# VERIFY DEPLOYMENT
# ============================================================================

verify_deployment() {
  local ssh_key="$1"
  log "Verifying remote deployment..."
  
  local cmd="
    PASSED=0
    TOTAL=0
    
    # Check directories
    for dir in $DEPLOYMENT_DIR/k8s-health-checks $DEPLOYMENT_DIR/security $DEPLOYMENT_DIR/multi-region $DEPLOYMENT_DIR/core; do
      TOTAL=\$((TOTAL + 1))
      if [ -d \"\$dir\" ]; then
        PASSED=\$((PASSED + 1))
      fi
    done
    
    # Check scripts
    for script in $DEPLOYMENT_DIR/k8s-health-checks/*.sh $DEPLOYMENT_DIR/security/*.sh $DEPLOYMENT_DIR/multi-region/*.sh $DEPLOYMENT_DIR/core/*.sh; do
      if [ -f \"\$script\" ]; then
        TOTAL=\$((TOTAL + 1))
        if [ -x \"\$script\" ] && bash -n \"\$script\" 2>/dev/null; then
          PASSED=\$((PASSED + 1))
        fi
      fi
    done
    
    echo \"Verification: \$PASSED/\$TOTAL checks passed\"
    
    if [ \$PASSED -eq \$TOTAL ]; then
      echo 'Verification PASSED'
      exit 0
    else
      echo 'Verification FAILED'
      exit 1
    fi
  "
  
  if execute_remote "$ssh_key" "$cmd"; then
    success "Remote verification passed"
  else
    error "Remote verification failed"
    return 1
  fi
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

print_summary() {
  echo ""
  log "╔═════════════════════════════════════════╗"
  log "║    ✅ REMOTE DEPLOYMENT COMPLETE        ║"
  log "║  100% Success - Worker Node Ready      ║"
  log "╚═════════════════════════════════════════╝"
  echo ""
  log "Deployment Summary:"
  log "  Remote Host: $TARGET_USER@$TARGET_HOST"
  log "  Deployment Dir: $DEPLOYMENT_DIR"
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
  log "Authentication: Service Account SSH (${SERVICE_ACCOUNT})"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo ""
  log "╔══════════════════════════════════════════════════════╗"
  log "║  WORKER NODE DEPLOYMENT - SERVICE ACCOUNT SSH AUTH  ║"
  log "╚══════════════════════════════════════════════════════╝"
  echo ""
  
  log "Target: $TARGET_USER@$TARGET_HOST"
  log "Service Account: $SERVICE_ACCOUNT"
  log "Session: $SESSION_ID"
  log ""
  
  # Check prerequisites (find SSH key and verify connectivity)
  check_prerequisites || return 1
  log ""
  
  # Get SSH key path
  SSH_KEY_PATH=$(detect_ssh_key) || return 1
  log ""
  
  # Prepare remote directories
  prepare_directories "$SSH_KEY_PATH" || return 1
  log ""
  
  # Deploy from git
  deploy_from_git "$SSH_KEY_PATH" || return 1
  log ""
  
  # Verify deployment
  verify_deployment "$SSH_KEY_PATH" || return 1
  log ""
  
  # Print summary
  print_summary
  
  return 0
}

# Execute
main "$@"
exit $?
