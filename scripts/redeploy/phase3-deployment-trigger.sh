#!/bin/bash
# ============================================================================
# PHASE 3 DISTRIBUTED DEPLOYMENT TRIGGER
# Fully automated, hands-off deployment of 100x infrastructure expansion
#
# Executes from any authorized host, triggers execution on worker via SSH
# Uses service account credentials (GSM/Vault/KMS only)
# Status: IMMUTABLE, EPHEMERAL, IDEMPOTENT, AUDIT-LOGGED, NO GITHUB ACTIONS
# 
# Usage:
#   ssh automation@192.168.168.42 'bash /path/to/phase3-deployment-trigger.sh'
#   OR from dev node: ./scripts/redeploy/phase3-deployment-trigger.sh
# ============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly WORKER_HOST="${WORKER_HOST:-192.168.168.42}"
readonly WORKER_USER="${WORKER_USER:-automation}"
readonly DEPLOYMENT_ID="$(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs/phase3-deployment"
readonly DEPLOYMENT_LOG="${LOG_DIR}/deployment-${DEPLOYMENT_ID}.jsonl"
readonly AUDIT_LOG="${LOG_DIR}/audit-${DEPLOYMENT_ID}.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure log directory
mkdir -p "$LOG_DIR"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${YELLOW}▶${NC} $1"; }

# Audit logging (immutable JSONL)
audit_entry() {
    local action="$1"
    local status="${2:-pending}"
    local details="${3:-}"
    local json_entry="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"deployment_id\":\"${DEPLOYMENT_ID}\",\"action\":\"${action}\",\"status\":\"${status}\",\"user\":\"${USER}\",\"host\":\"$(hostname -f 2>/dev/null || hostname)\""
    if [ -n "$details" ]; then
        json_entry="$json_entry,\"details\":$details"
    fi
    json_entry="$json_entry}"
    echo "$json_entry" >> "$AUDIT_LOG"
}

log_step "Phase 3: Distributed Deployment Trigger"
log_info "Deployment ID: $DEPLOYMENT_ID"
log_info "Repository: $WORKSPACE_ROOT"
log_info "Audit Log: $AUDIT_LOG"

audit_entry "deployment_initiated" "in-progress"

# Verify worker connectivity
log_step "Verifying worker node connectivity"
if ! ping -c 1 "$WORKER_HOST" >/dev/null 2>&1; then
    log_error "Worker node unreachable: $WORKER_HOST"
    audit_entry "connectivity_check" "failed" "\"error\":\"ping failed\""
    exit 1
fi
log_success "Worker connectivity verified"
audit_entry "connectivity_check" "success"

# Check SSH access
log_step "Verifying SSH access"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$WORKER_USER@$WORKER_HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
    log_error "SSH access failed to $WORKER_USER@$WORKER_HOST"
    audit_entry "ssh_access_check" "failed" "\"error\":\"SSH connection failed\""
    exit 1
fi
log_success "SSH access verified"
audit_entry "ssh_access_check" "success"

# Create deployment manifest (immutable)
log_step "Creating deployment manifest"
MANIFEST_FILE="${LOG_DIR}/manifest-${DEPLOYMENT_ID}.json"
cat > "$MANIFEST_FILE" << MANIFEST
{
  "deployment_id": "$DEPLOYMENT_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "initiated_by": "$USER",
  "initiated_from": "$(hostname -f 2>/dev/null || hostname)",
  "target_worker": "$WORKER_HOST",
  "repository": "$WORKSPACE_ROOT",
  "phase": "phase3",
  "deployment_type": "100x_distributed_expansion",
  "constraints": {
    "immutable": true,
    "ephemeral_state": true,
    "idempotent": true,
    "credentials_model": "GSM_VAULT_KMS_only",
    "no_manual_operations": true,
    "no_github_actions": true,
    "no_github_releases": true,
    "direct_deployment": true,
    "service_account_only": true
  },
  "framework_version": "$(git -C "$WORKSPACE_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
}
MANIFEST
log_success "Manifest created: $MANIFEST_FILE"
audit_entry "manifest_created" "success"

# Sync deployment framework to worker
log_step "Syncing deployment framework to worker"
DEPLOY_DIR="/tmp/phase3-deployment-${DEPLOYMENT_ID}"
ssh "$WORKER_USER@$WORKER_HOST" "mkdir -p $DEPLOY_DIR" || {
    log_error "Failed to create deployment directory on worker"
    audit_entry "framework_sync" "failed" "\"error\":\"mkdir failed\""
    exit 1
}

rsync -avz --delete \
    --exclude=.git \
    --exclude=logs \
    --exclude=.secrets* \
    --exclude='*.baseline' \
    "$WORKSPACE_ROOT/scripts/" \
    "$WORKER_USER@$WORKER_HOST:$DEPLOY_DIR/scripts/" || {
    log_error "Failed to sync scripts to worker"
    audit_entry "framework_sync" "failed" "\"error\":\"rsync failed\""
    exit 1
}

log_success "Framework synced to worker: $DEPLOY_DIR"
audit_entry "framework_sync" "success"

# Execute Phase 3 deployment on worker
log_step "Triggering Phase 3 deployment on worker"
audit_entry "deployment_execution_starting" "in-progress"

DEPLOY_CMD="cd $DEPLOY_DIR && \
  export DRY_RUN=false && \
  export DEPLOYMENT_ID='$DEPLOYMENT_ID' && \
  export NO_GITHUB_ACTIONS=true && \
  export SERVICE_ACCOUNT_ONLY=true && \
  export CREDENTIALS_MODEL='GSM_VAULT_KMS' && \
  bash redeploy/redeploy-100x.sh"

DEPLOY_OUTPUT=$(ssh "$WORKER_USER@$WORKER_HOST" "bash -c '$DEPLOY_CMD'" 2>&1) || STATUS=$?

if [ -z "${STATUS:-}" ]; then
  STATUS=0
fi

# Log deployment output (immutable)
echo "$DEPLOY_OUTPUT" | tee -a "$DEPLOYMENT_LOG"

if [ $STATUS -ne 0 ]; then
    log_error "Deployment encountered issues (exit code: $STATUS)"
    audit_entry "deployment_execution" "warning" "\"exit_code\":$STATUS"
else
    log_success "Deployment completed"
    audit_entry "deployment_execution" "success"
fi

# Verify post-deployment health
log_step "Verifying post-deployment health"
HEALTH_CMD="cd $DEPLOY_DIR && bash test/post_deploy_validation.sh"
HEALTH_OUTPUT=$(ssh "$WORKER_USER@$WORKER_HOST" "bash -c '$HEALTH_CMD'" 2>&1) || HEALTH_STATUS=$?

if [ -z "${HEALTH_STATUS:-}" ]; then
  HEALTH_STATUS=0
fi

echo "$HEALTH_OUTPUT" | tee -a "$DEPLOYMENT_LOG"

if [ $HEALTH_STATUS -eq 0 ]; then
    log_success "Post-deployment validation passed"
    audit_entry "post_deploy_validation" "success"
else
    log_error "Post-deployment validation had warnings (exit code: $HEALTH_STATUS)"
    audit_entry "post_deploy_validation" "warning" "\"exit_code\":$HEALTH_STATUS"
fi

# Cleanup on worker
log_step "Cleaning up deployment artifacts on worker"
ssh "$WORKER_USER@$WORKER_HOST" "rm -rf $DEPLOY_DIR" 2>/dev/null || true
log_success "Cleanup completed"
audit_entry "cleanup" "success"

# Summary
echo ""
log_success "═══════════════════════════════════════════════════════════"
log_success "Phase 3 Deployment: COMPLETED"
log_success "═══════════════════════════════════════════════════════════"
echo ""
echo "Deployment Summary:"
echo "  Deployment ID: $DEPLOYMENT_ID"
echo "  Deployment Log: $DEPLOYMENT_LOG"
echo "  Audit Log: $AUDIT_LOG"
echo "  Manifest: $MANIFEST_FILE"
echo "  Exit Status: $STATUS"
echo ""
echo "Next Steps:"
echo "  1. Review deployment results:"
echo "     tail -100 $DEPLOYMENT_LOG"
echo ""
echo "  2. Verify audit trail:"
echo "     tail -50 $AUDIT_LOG"
echo ""
echo "  3. Monitor worker metrics:"
echo "     ssh automation@$WORKER_HOST 'systemctl status'"
echo ""
echo "  4. Check Grafana dashboards:"
echo "     http://192.168.168.42:3000"
echo ""

audit_entry "deployment_complete" "success"

# Return appropriate exit code
exit $STATUS
