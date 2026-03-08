#!/bin/bash
set -euo pipefail

##############################################################################
# Phase 5 Post-Activation Validation Script
# Purpose: Validate that workflows run successfully after secret provisioning
# Usage: ./scripts/automation/post-activation-validation.sh
##############################################################################

REPO="${REPO:-kushin77/self-hosted-runner}"
GH_CMD="gh"
TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-10}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[✔]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_fail() { echo -e "${RED}[✘]${NC} $1"; }

##############################################################################

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}Phase 5 Post-Activation Validation${NC}"
echo -e "${BLUE}Repository: ${REPO}${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Trigger workflows and monitor
log_info "Step 1: Triggering GSM sync workflow..."
GSM_RUN_ID=$($GH_CMD workflow run sync-gsm-to-github-secrets.yml -R "$REPO" --ref main 2>&1 | grep -oP 'at \K[\w-]+' | head -1 || echo "")

if [ -z "$GSM_RUN_ID" ]; then
    log_warn "Could not parse run ID from workflow creation; monitoring by timestamp"
    GSM_RUN_ID="latest"
fi

sleep 2

log_info "Step 2: Waiting for GSM sync to complete (max ${TIMEOUT_MINUTES} minutes)..."
GSM_STATUS="in_progress"
GSM_CONCLUSION=""
START_TIME=$(date +%s)
DEADLINE=$((START_TIME + TIMEOUT_MINUTES * 60))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    INFO=$($GH_CMD run list --workflow=sync-gsm-to-github-secrets.yml -R "$REPO" --limit 1 --json status,conclusion,databaseId --jq '.[] | {status:.status, conclusion:.conclusion, id:.databaseId}' 2>/dev/null || echo "")
    
    if [ -n "$INFO" ]; then
        GSM_STATUS=$(echo "$INFO" | jq -r '.status')
        GSM_CONCLUSION=$(echo "$INFO" | jq -r '.conclusion')
        GSM_RUN_ID=$(echo "$INFO" | jq -r '.id')
        
        echo -ne "\r[${GSM_STATUS}] GSM sync run #${GSM_RUN_ID}..."
        
        if [ "$GSM_STATUS" != "in_progress" ]; then
            echo ""
            break
        fi
    fi
    sleep 5
done

if [ "$GSM_STATUS" = "completed" ] && [ "$GSM_CONCLUSION" = "success" ]; then
    log_pass "GSM sync succeeded"
else
    log_fail "GSM sync status: $GSM_STATUS, conclusion: $GSM_CONCLUSION"
    log_info "Check logs: https://github.com/${REPO}/actions/runs/${GSM_RUN_ID}"
fi
echo ""

log_info "Step 3: Triggering runner-self-heal workflow..."
HEAL_RUN_ID=$($GH_CMD workflow run runner-self-heal.yml -R "$REPO" --ref main 2>&1 | grep -oP 'at \K[\w-]+' | head -1 || echo "")

sleep 2

log_info "Step 4: Waiting for runner-self-heal to complete (max ${TIMEOUT_MINUTES} minutes)..."
HEAL_STATUS="in_progress"
HEAL_CONCLUSION=""
START_TIME=$(date +%s)
DEADLINE=$((START_TIME + TIMEOUT_MINUTES * 60))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    INFO=$($GH_CMD run list --workflow=runner-self-heal.yml -R "$REPO" --limit 1 --json status,conclusion,databaseId --jq '.[] | {status:.status, conclusion:.conclusion, id:.databaseId}' 2>/dev/null || echo "")
    
    if [ -n "$INFO" ]; then
        HEAL_STATUS=$(echo "$INFO" | jq -r '.status')
        HEAL_CONCLUSION=$(echo "$INFO" | jq -r '.conclusion')
        HEAL_RUN_ID=$(echo "$INFO" | jq -r '.id')
        
        echo -ne "\r[${HEAL_STATUS}] Self-heal run #${HEAL_RUN_ID}..."
        
        if [ "$HEAL_STATUS" != "in_progress" ]; then
            echo ""
            break
        fi
    fi
    sleep 5
done

if [ "$HEAL_STATUS" = "completed" ] && [ "$HEAL_CONCLUSION" = "success" ]; then
    log_pass "Runner self-heal succeeded"
elif [ "$HEAL_STATUS" = "completed" ] && [ "$HEAL_CONCLUSION" = "neutral" ]; then
    log_pass "Runner self-heal completed (neutral — no offline runners detected)"
else
    log_warn "Runner self-heal status: $HEAL_STATUS, conclusion: $HEAL_CONCLUSION"
    log_info "Check logs: https://github.com/${REPO}/actions/runs/${HEAL_RUN_ID}"
fi
echo ""

# Verify recent runs
log_info "Step 5: Verifying recent workflow executions..."
RECENT=$($GH_CMD run list -R "$REPO" --limit 10 --json name,status,conclusion --jq '.[] | select(.status=="completed") | "\(.name): \(.conclusion)"' 2>/dev/null | head -5 || echo "")

if [ -n "$RECENT" ]; then
    echo "$RECENT" | while read -r line; do
        if echo "$line" | grep -q "success"; then
            log_pass "$line"
        elif echo "$line" | grep -q "failure"; then
            log_fail "$line"
        fi
    done
else
    log_warn "No recent completed runs yet; workflows may be in progress"
fi
echo ""

# Summary
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}VALIDATION SUMMARY${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

GSM_OK=false
HEAL_OK=false

[ "$GSM_STATUS" = "completed" ] && [ "$GSM_CONCLUSION" = "success" ] && GSM_OK=true
[ "$HEAL_STATUS" = "completed" ] && ([ "$HEAL_CONCLUSION" = "success" ] || [ "$HEAL_CONCLUSION" = "neutral" ]) && HEAL_OK=true

echo "GSM Sync:        $([ "$GSM_OK" = true ] && echo -e "${GREEN}✓ PASS${NC}" || echo -e "${RED}✗ FAIL${NC}")"
echo "Runner Self-Heal: $([ "$HEAL_OK" = true ] && echo -e "${GREEN}✓ PASS${NC}" || echo -e "${RED}✗ FAIL${NC}")"
echo ""

if [ "$GSM_OK" = true ] && [ "$HEAL_OK" = true ]; then
    echo -e "${GREEN}✅ Phase 5 activation successful!${NC}"
    echo ""
    echo "Phase 5 is now fully operational. Scheduled workflows will:"
    echo "  • Sync GSM secrets every 6 hours"
    echo "  • Check runner health every 5 minutes"
    echo "  • Rotate credentials monthly and quarterly"
    echo "  • Send alerts to Slack (if configured)"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Activation validation failed.${NC}"
    echo ""
    echo "Troubleshooting:"
    if [ "$GSM_OK" != true ]; then
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
        echo "  • Check: gh run view ${GSM_RUN_ID} -R $REPO --log"
    fi
    if [ "$HEAL_OK" != true ]; then
        echo "  • Runner self-heal failed; verify RUNNER_MGMT_TOKEN has correct scopes"
        echo "  • Check: gh run view ${HEAL_RUN_ID} -R $REPO --log"
    fi
    echo ""
    exit 1
fi
