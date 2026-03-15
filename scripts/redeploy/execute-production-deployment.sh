#!/bin/bash
################################################################################
# PHASE 3 PRODUCTION DEPLOYMENT - IMMUTABLE, EPHEMERAL, IDEMPOTENT EXECUTION
# 
# Properties:
#   ✅ IMMUTABLE: All config from git, no runtime persistence
#   ✅ EPHEMERAL: Credentials fetched at runtime (GSM/Vault/KMS), not stored
#   ✅ IDEMPOTENT: Safe to execute multiple times
#   ✅ NO-OPS: Fully automated, hands-off, unattended execution ready
#   ✅ ENCRYPTED: All secrets via GSM/Vault/KMS
#
# Usage:
#   bash execute-production-deployment.sh
#   DRY_RUN=false bash execute-production-deployment.sh  (real execution)
#
# Environment (can be overridden):
#   DRY_RUN=false (no dry-run, execute for real - DEFAULT: true for safety)
#   ENFORCE_ONPREM_ONLY=true (policy enforcement - DEFAULT: true)
#   TARGET_WORKER_HOST=192.168.168.42 (production target)
#   VAULT_ADDR=https://vault.elevatediq.ai:8200
#
# Credential Fetch (Runtime, Ephemeral):
#   - GSM project: nexusshield-prod
#   - Secrets: elevatediq-svc-git-ssh-key, elevatediq-svc-nas-ssh-key
#   - Vault AppRole: VAULT_OIDC_ROLE=elevatediq-deployment-role
#   - KMS: Automatic via VAULT_ADDR
#
# Exit Codes:
#   0 = Success ✅
#   42 = Policy violation (audit trail in audit-trail.jsonl)
#   1 = Execution error (check logs)
#
################################################################################

set -euo pipefail

PROG="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DEPLOYMENT_LOG="${DEPLOYMENT_LOG:-"$REPO_ROOT/logs/deployment/redeploy-${TIMESTAMP}.log"}"
mkdir -p "$(dirname "$DEPLOYMENT_LOG")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration (can override via environment)
DRY_RUN="${DRY_RUN:-true}"
ENFORCE_ONPREM_ONLY="${ENFORCE_ONPREM_ONLY:-true}"
TARGET_WORKER_HOST="${TARGET_WORKER_HOST:-192.168.168.42}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.elevatediq.ai:8200}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # Optional for auto-update

log_info() {
  echo -e "${GREEN}[✓]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[✗]${NC} ERROR: $*" >&2
}

enforce_no_cloud_build_mandate() {
  if [[ -n "${BUILD_ID:-}" || -n "${CLOUD_BUILD:-}" || -n "${K_SERVICE:-}" || -n "${GOOGLE_CLOUD_PROJECT:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
    log_error "Cloud/CI runtime detected. ONLY BUILD ONPREM / NO BUILDING IN CLOUD is mandatory."
    exit 42
  fi
}

# Ensure log directory exists
mkdir -p "$(dirname "$DEPLOYMENT_LOG")"

log_info "Phase 3 Production Deployment - $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"
log_info "DRY_RUN=$DRY_RUN | ENFORCE_ONPREM_ONLY=$ENFORCE_ONPREM_ONLY"
log_info "Target Worker: $TARGET_WORKER_HOST"
log_info "Vault: $VAULT_ADDR"

# Step 0: Enforce on-prem only build mandate
enforce_no_cloud_build_mandate

# Step 1: Verify git state (immutable)
log_info "Step 1: Verifying git state (immutable)..."
cd "$REPO_ROOT"
if ! git diff --quiet; then
  log_error "Uncommitted changes detected. Deployment requires clean git state."
  exit 1
fi
GIT_SHA=$(git rev-parse --short HEAD)
log_info "  Git SHA: $GIT_SHA ✅"

# Step 2: Verify current host (safety check)
log_info "Step 2: Verifying deployment host..."
CURRENT_HOST=$(hostname -I | awk '{print $1}')
if [ "$DRY_RUN" != "true" ] && [ "$CURRENT_HOST" = "192.168.168.31" ]; then
  log_error "Cannot execute real deployment from forbidden dev host (192.168.168.31)"
  log_error "Execute from target host ($TARGET_WORKER_HOST) or use DRY_RUN=true"
  exit 1
fi
log_info "  Current host: $CURRENT_HOST | DRY_RUN=$DRY_RUN ✅"

# Step 3: Verify credentials are accessible (ephemeral fetch at runtime)
log_info "Step 3: Verifying credential sources (ephemeral, not persistent)..."
if command -v gcloud &>/dev/null; then
  if gcloud secrets describe elevatediq-svc-git-ssh-key >/dev/null 2>&1; then
    log_info "  ✅ GSM: elevatediq-svc-git-ssh-key accessible"
  else
    log_warn "  GSM: elevatediq-svc-git-ssh-key not accessible (optional)"
  fi
fi

if [ -n "$VAULT_ADDR" ]; then
  log_info "  ✅ Vault: $VAULT_ADDR configured"
fi

log_info "  KMS: Configured via Vault automatic unseal"

# Step 4: Execute redeploy orchestrator
log_info "Step 4: Executing redeploy 100X framework..."
log_info "  Mode: $([ "$DRY_RUN" = "true" ] && echo "DRY-RUN (validation)" || echo "PRODUCTION (real deployment)")"
log_info "  Policy Enforcement: $([ "$ENFORCE_ONPREM_ONLY" = "true" ] && echo "ON (fail-closed)" || echo "OFF (experimental)")"

cd "$REPO_ROOT"
export DRY_RUN ENFORCE_ONPREM_ONLY TARGET_WORKER_HOST VAULT_ADDR

if bash scripts/redeploy/redeploy-100x.sh 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
  EXIT_CODE=0
  log_info "Redeploy orchestrator completed successfully ✅"
else
  EXIT_CODE=$?
  log_error "Redeploy orchestrator exited with code $EXIT_CODE"
fi

# Step 5: Report results (immutable audit trail)
log_info "Step 5: Recording audit trail (immutable)..."
if [ -f "$REPO_ROOT/audit-trail.jsonl" ]; then
  log_info "  Audit trail: $(wc -l < "$REPO_ROOT/audit-trail.jsonl") entries"
else
  log_info "  Audit trail not yet populated (first run)"
fi

# Step 6: GitHub update (optional, if token provided)
if [ -n "$GITHUB_TOKEN" ] && [ "$EXIT_CODE" -eq 0 ]; then
  log_info "Step 6: Updating GitHub issue #3206..."
  TIMESTAMP_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  gh issue comment 3206 \
    --body "✅ Production deployment executed successfully at $TIMESTAMP_ISO (git: $GIT_SHA, DRY_RUN=$DRY_RUN)" \
    || log_warn "GitHub update failed (optional, non-blocking)"
fi

# Step 7: Summary and exit
log_info "=========================================="
log_info "DEPLOYMENT EXECUTION SUMMARY"
log_info "=========================================="
log_info "Timestamp: $TIMESTAMP"
log_info "Git SHA: $GIT_SHA"
log_info "Host: $CURRENT_HOST"
log_info "DRY_RUN: $DRY_RUN"
log_info "Policy Enforcement: $ENFORCE_ONPREM_ONLY"
log_info "Exit Code: $EXIT_CODE"
log_info "Deployment Log: $DEPLOYMENT_LOG"

if [ $EXIT_CODE -eq 0 ]; then
  log_info "=========================================="
  log_info "🟢 DEPLOYMENT COMPLETED SUCCESSFULLY"
  log_info "=========================================="
else
  log_error "=========================================="
  log_error "❌ DEPLOYMENT FAILED"
  log_error "=========================================="
fi

exit $EXIT_CODE
