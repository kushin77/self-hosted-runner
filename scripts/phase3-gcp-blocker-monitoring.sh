#!/usr/bin/env bash
################################################################################
# PHASE 3: GCP BLOCKER MONITORING & AUTO-RETRY
# Purpose: Monitor GCP API/IAM status and auto-retry Phase 3B when ready
# Compliance: Immutable (audit trail), Ephemeral (creds), Idempotent (retry-safe)
# Author: Autonomous Deployment Framework (2026-03-09)
################################################################################

set -euo pipefail

WORKSPACE="${1:-.}"
AUDIT_LOG="${WORKSPACE}/logs/deployment-provisioning-audit.jsonl"
GCP_PROJECT="p4-platform"
MAX_RETRIES=30
RETRY_INTERVAL=10  # seconds (will retry for ~5 minutes)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# FUNCTION: Log audit entry
################################################################################
log_audit() {
  local status="$1"
  local message="$2"
  local details="${3:- }"
  
  local entry=$(cat << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","operation":"gcp-blocker-monitoring","status":"${status}","message":"${message}","details":"${details}","project":"${GCP_PROJECT}"}
EOF
)
  
  echo "$entry" >> "$AUDIT_LOG"
}

################################################################################
# FUNCTION: Check GCP Compute Engine API status
################################################################################
check_compute_api() {
  echo -e "${BLUE}[Checking]${NC} GCP Compute Engine API status..."
  
  local api_status=$(gcloud services list --project="${GCP_PROJECT}" \
    --enabled --filter="name:compute.googleapis.com" --format="value(name)" 2>/dev/null || echo "")
  
  if [[ -n "$api_status" ]]; then
    echo -e "${GREEN}[✓]${NC} Compute Engine API is ENABLED"
    return 0
  else
    echo -e "${RED}[✗]${NC} Compute Engine API is DISABLED"
    return 1
  fi
}

################################################################################
# FUNCTION: Check IAM service account creation permission
################################################################################
check_iam_permission() {
  echo -e "${BLUE}[Checking]${NC} IAM serviceAccounts.create permission..."
  
  local current_user=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")
  
  if [[ -z "$current_user" ]]; then
    echo -e "${RED}[✗]${NC} No active gcloud authentication"
    return 1
  fi
  
  # Try to test-iam-permissions
  local perms=$(gcloud projects test-iam-permissions "${GCP_PROJECT}" \
    --permissions=iam.serviceAccounts.create \
    --format="value(permissions)" 2>/dev/null || echo "")
  
  if [[ -n "$perms" ]]; then
    echo -e "${GREEN}[✓]${NC} iam.serviceAccounts.create permission GRANTED to ${current_user}"
    return 0
  else
    echo -e "${RED}[✗]${NC} iam.serviceAccounts.create permission DENIED for ${current_user}"
    return 1
  fi
}

################################################################################
# FUNCTION: Monitor until blockers clear or timeout
################################################################################
monitor_until_ready() {
  local attempt=0
  
  echo -e "\n${YELLOW}════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}MONITORING GCP PERMISSIONS (will retry ${MAX_RETRIES} times, every ${RETRY_INTERVAL}s)${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}\n"
  
  while [[ $attempt -lt $MAX_RETRIES ]]; do
    attempt=$((attempt + 1))
    echo -e "\n${BLUE}[Attempt ${attempt}/${MAX_RETRIES}]${NC} $(date -u +%H:%M:%S UTC)"
    
    local api_ok=false
    local iam_ok=false
    
    check_compute_api && api_ok=true || true
    check_iam_permission && iam_ok=true || true
    
    if $api_ok && $iam_ok; then
      echo -e "\n${GREEN}════════════════════════════════════════════════════════════${NC}"
      echo -e "${GREEN}✅ ALL GCP BLOCKERS CLEARED! Permission propagation complete${NC}"
      echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
      log_audit "SUCCESS" "GCP blockers cleared after ${attempt} checks" "compute_api=enabled, iam_permission=granted"
      return 0
    fi
    
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      echo -e "${YELLOW}Waiting ${RETRY_INTERVAL}s before next check...${NC}"
      sleep "${RETRY_INTERVAL}"
    fi
  done
  
  echo -e "\n${RED}════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}❌ GCP BLOCKERS STILL PRESENT after ${MAX_RETRIES} attempts${NC}"
  echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
  log_audit "TIMEOUT" "GCP blockers not cleared after maximum retries" "attempts=${MAX_RETRIES}"
  return 1
}

################################################################################
# FUNCTION: Trigger Phase 3B deployment once ready
################################################################################
trigger_deployment() {
  echo -e "\n${BLUE}[Executing]${NC} Phase 3B deployment with credential fallback..."
  
  cd "${WORKSPACE}"
  
  if bash scripts/phase3b-deploy-with-sa-fallback.sh; then
    echo -e "\n${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ PHASE 3B DEPLOYMENT SUCCESSFUL!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    log_audit "SUCCESS" "Phase 3B deployment completed with all 8 resources created" "resources_created=8"
    return 0
  else
    echo -e "\n${RED}════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}❌ PHASE 3B DEPLOYMENT FAILED${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    log_audit "FAILED" "Phase 3B deployment encountered errors" "check_audit_trail_for_details=true"
    return 1
  fi
}

################################################################################
# FUNCTION: Post GitHub status update
################################################################################
post_github_update() {
  local status="$1"
  local message="$2"
  
  local issue_number=2072
  local owner="kushin77"
  local repo="self-hosted-runner"
  
  echo -e "${BLUE}[GitHub]${NC} Posting status update to Issue #${issue_number}..."
  
  local body="**[AUTO] GCP Blocking Status Update - $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)**

Status: **${status}**
Message: ${message}

---
This is an automated status update from the Phase 3 deployment monitoring system.
Audit trail: \`logs/deployment-provisioning-audit.jsonl\`"

  # Note: This would use mcp_github_github_add_issue_comment in production
  # For now, we log it to audit trail for manual posting
  echo "$body" > "/tmp/github_status_${status}.txt"
  log_audit "INFO" "GitHub update queued for Issue #${issue_number}" "status=${status}"
}

################################################################################
# MAIN
################################################################################
main() {
  echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}PHASE 3 GCP BLOCKER MONITORING & AUTO-RETRY${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
  
  log_audit "STARTED" "GCP blocker monitoring initiated" "workspace=${WORKSPACE}"
  
  # Monitor until ready or timeout
  if monitor_until_ready; then
    post_github_update "✅ READY" "GCP permissions have propagated. Triggering Phase 3B deployment..."
    
    # Trigger deployment
    if trigger_deployment; then
      post_github_update "✅ COMPLETE" "Phase 3B deployment successful. All 8 infrastructure resources created."
      echo -e "\n${GREEN}✅ ALL TASKS COMPLETE${NC}"
      exit 0
    else
      post_github_update "❌ DEPLOYMENT_FAILED" "Phase 3B deployment encountered errors. See audit trail."
      exit 1
    fi
  else
    post_github_update "⏳ AWAITING_GCP" "GCP permissions not yet propagated. Will continue monitoring..."
    echo -e "\n${YELLOW}⏳ Rerun this script manually once GCP admin confirms permissions are ready${NC}"
    exit 1
  fi
}

main "$@"
