#!/bin/bash

################################################################################
# Production Deployment Automation - Immutable, Ephemeral, Idempotent
# NO GitHub Actions | NO PR Releases | Direct Deployment
# GSM/Vault/KMS for all credentials | Fully Automated | Hands-Off
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOYMENT_DIR="${PROJECT_ROOT}/logs/deployments"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOYMENT_ID="${TIMESTAMP}-$(uuidgen | cut -d'-' -f1)"

mkdir -p "$DEPLOYMENT_DIR"
DEPLOYMENT_LOG="${DEPLOYMENT_DIR}/deployment-${DEPLOYMENT_ID}.jsonl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_json() {
  local level=$1
  local message=$2
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"deployment_id\":\"$DEPLOYMENT_ID\",\"message\":\"$message\"}" >> "$DEPLOYMENT_LOG"
}

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; log_json "INFO" "$*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; log_json "ERROR" "$*"; }

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  log "🚀 PRODUCTION DEPLOYMENT AUTOMATION STARTED"
  log "Deployment ID: $DEPLOYMENT_ID"
  log_json "START" "Production deployment initiated"
  
  cd "$PROJECT_ROOT"
  bash scripts/orchestration/hardening-master.sh --phase all --execute 2>&1 | tail -50
  
  log_json "COMPLETE" "Deployment successful"
  success "🟢 PRODUCTION DEPLOYMENT COMPLETE"
}

main "$@"
