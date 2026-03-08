#!/bin/bash
set -euo pipefail

##############################################################################
# Phase 5 Ops Verification Script
# Purpose: Validate secrets provisioning and workflow readiness
# Usage: ./scripts/automation/verify-secrets-provisioned.sh
##############################################################################

REPO="${REPO:-kushin77/self-hosted-runner}"
GH_CMD="gh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verification counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_WARNING=0
CHECKS_FAILED=0

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNING++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

check_secret() {
    local secret_name=$1
    local required=${2:-true}
    ((CHECKS_TOTAL++))
    
    # Check if secret exists
    if $GH_CMD secret list --repo "$REPO" | grep -q "^${secret_name}$"; then
        log_pass "Secret '${secret_name}' is provisioned"
        return 0
    else
        if [ "$required" = "true" ]; then
            log_fail "Required secret '${secret_name}' is MISSING"
            return 1
        else
            log_warn "Optional secret '${secret_name}' is not provisioned"
            return 0
        fi
    fi
}

check_workflow() {
    local workflow_file=$1
    ((CHECKS_TOTAL++))
    
    if [ -f ".github/workflows/${workflow_file}" ]; then
        log_pass "Workflow '${workflow_file}' is deployed"
        return 0
    else
        log_fail "Workflow '${workflow_file}' is MISSING"
        return 1
    fi
}

check_workflow_enabled() {
    local workflow_file=$1
    ((CHECKS_TOTAL++))
    
    if $GH_CMD api repos/"$REPO"/actions/workflows/"${workflow_file}" --jq '.state' 2>/dev/null | grep -q "active"; then
        log_pass "Workflow '${workflow_file}' is enabled"
        return 0
    else
        log_warn "Workflow '${workflow_file}' may not be enabled; check manually"
        return 0
    fi
}

##############################################################################

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}Phase 5 Operations Verification${NC}"
echo -e "${BLUE}Repository: ${REPO}${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Section 1: Required Secrets
echo -e "${BLUE}1. REQUIRED SECRETS (Blocking)${NC}"
echo ""
check_secret "GCP_SERVICE_ACCOUNT_KEY" true
check_secret "GCP_PROJECT_ID" true
check_secret "RUNNER_MGMT_TOKEN" true
check_secret "DEPLOY_SSH_KEY" true
echo ""

# Section 2: Optional Secrets
echo -e "${BLUE}2. OPTIONAL SECRETS${NC}"
echo ""
check_secret "SLACK_WEBHOOK_URL" false
echo ""

# Section 3: Required Workflows
echo -e "${BLUE}3. REQUIRED WORKFLOWS${NC}"
echo ""
check_workflow "sync-gsm-to-github-secrets.yml"
check_workflow "runner-self-heal.yml"
check_workflow "credential-rotation-monthly.yml"
check_workflow "vault-approle-rotation-quarterly.yml"
check_workflow "slack-notifications.yml"
echo ""

# Section 4: Workflow Enablement
echo -e "${BLUE}4. WORKFLOW ENABLEMENT${NC}"
echo ""
check_workflow_enabled "sync-gsm-to-github-secrets.yml"
check_workflow_enabled "runner-self-heal.yml"
echo ""

# Section 5: Recent Workflow Runs
echo -e "${BLUE}5. RECENT WORKFLOW RUNS${NC}"
echo ""
((CHECKS_TOTAL++))

echo "Fetching recent runs from GitHub Actions..."
RECENT_RUNS=$($GH_CMD run list -R "$REPO" --limit 5 --json name,status,conclusion --jq '.[] | "\(.name): \(.status) (\(.conclusion))"' 2>/dev/null || echo "")

if [ -n "$RECENT_RUNS" ]; then
    echo "$RECENT_RUNS" | head -5
    log_pass "Workflow runs are being tracked"
else
    log_warn "No recent workflow runs; workflows may not have triggered yet"
fi
echo ""

# Section 6: Repository Settings
echo -e "${BLUE}6. REPOSITORY SETTINGS${NC}"
echo ""
((CHECKS_TOTAL++))

# Check if branch protection is enabled
BRANCH_PROTECTED=$($GH_CMD api repos/"$REPO"/branches/main --jq '.protected' 2>/dev/null || echo "false")
if [ "$BRANCH_PROTECTED" = "true" ]; then
    log_pass "Branch 'main' is protected"
else
    log_warn "Branch 'main' may not be protected; consider enabling"
fi
echo ""

# Summary
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}SUMMARY${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "Total checks: ${CHECKS_TOTAL}"
echo -e "✅ Passed:   ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "⚠️  Warnings: ${YELLOW}${CHECKS_WARNING}${NC}"
echo -e "❌ Failed:   ${RED}${CHECKS_FAILED}${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All critical checks passed! Phase 5 is ready to activate.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Trigger GSM sync: gh workflow run sync-gsm-to-github-secrets.yml -R $REPO --ref main"
    echo "  2. Monitor: gh run list -R $REPO --workflow=sync-gsm-to-github-secrets.yml"
    echo "  3. Trigger self-heal: gh workflow run runner-self-heal.yml -R $REPO --ref main"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Critical checks failed. Please fix before proceeding.${NC}"
    echo ""
    echo "Remediation:"
    echo "  - See PHASE_5_OPS_HANDOFF.md for detailed steps"
    echo "  - See issue #1038 for copy-paste secret provisioning commands"
    echo ""
    exit 1
fi
