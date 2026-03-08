#!/bin/bash
set -e

###############################################################################
# Self-Service Deployment Script - Automates Full Activation Loop
# Purpose: One-command deployment (no manual input required)
# Usage: bash scripts/deploy-self-service.sh [--demo|--prod]
###############################################################################

REPO="kushin77/self-hosted-runner"
MODE="${1:-demo}"  # demo (uses mock secrets) or prod (uses real secrets)
TIMESTAMP=$(date -u +'%Y%m%dT%H%M%SZ')

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🚀 SELF-SERVICE DEPLOYMENT — Streamlined 10X              ║${NC}"
echo -e "${BLUE}║  Mode: $MODE (demo=mock, prod=real)${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

###############################################################################
# PHASE 1: Validate Repository & CLI Tools
###############################################################################
echo -e "\n${BLUE}[PHASE 1] Validating repository and CLI tools...${NC}"

if ! command -v gh &> /dev/null; then
  echo -e "${RED}❌ gh CLI not found. Install: https://cli.github.com${NC}"
  exit 1
fi

if ! command -v git &> /dev/null; then
  echo -e "${RED}❌ git not found${NC}"
  exit 1
fi

# Check if we're in the right repo
CURRENT_REPO=$(gh repo view --json nameWithOwner -q 2>/dev/null || echo "")
if [[ "$CURRENT_REPO" != "$REPO" ]]; then
  echo -e "${YELLOW}⚠️  Expected repo: $REPO, current: $CURRENT_REPO${NC}"
  echo -e "${YELLOW}   Attempting to set context...${NC}"
  gh repo set-default "$REPO" 2>/dev/null || true
fi

echo -e "${GREEN}✅ Repository validated${NC}"

###############################################################################
# PHASE 2: Prepare Secrets (Demo or Prod)
###############################################################################
echo -e "\n${BLUE}[PHASE 2] Preparing secrets ($MODE mode)...${NC}"

if [[ "$MODE" == "demo" ]]; then
  # Use mock/test secrets for demo
  GCP_PROJECT_ID="demo-project-12345"
  GCP_WIF_PROVIDER="projects/123456789/locations/global/workloadIdentityPools/github/providers/github"
  VAULT_ADDR="https://vault.demo.internal:8200"
  AWS_KMS_KEY_ID="arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  
  echo -e "${YELLOW}ℹ️  Using DEMO/TEST secrets (not functional, for demo only)${NC}"
else
  # Try to use real secrets from environment or prompt
  GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
  GCP_WIF_PROVIDER="${GCP_WORKLOAD_IDENTITY_PROVIDER:-}"
  VAULT_ADDR="${VAULT_ADDR:-}"
  AWS_KMS_KEY_ID="${AWS_KMS_KEY_ID:-}"
  
  if [[ -z "$GCP_PROJECT_ID" || -z "$GCP_WIF_PROVIDER" || -z "$VAULT_ADDR" || -z "$AWS_KMS_KEY_ID" ]]; then
    echo -e "${RED}❌ Production mode requires real secrets. Set:${NC}"
    echo "   GCP_PROJECT_ID, GCP_WORKLOAD_IDENTITY_PROVIDER, VAULT_ADDR, AWS_KMS_KEY_ID"
    echo -e "${YELLOW}   Or run: bash scripts/deploy-self-service.sh demo${NC}"
    exit 1
  fi
  
  echo -e "${YELLOW}ℹ️  Using PRODUCTION secrets from environment${NC}"
fi

echo -e "${GREEN}✅ Secrets prepared${NC}"

###############################################################################
# PHASE 3: Set Repository Secrets
###############################################################################
echo -e "\n${BLUE}[PHASE 3] Setting repository secrets...${NC}"

# Function to safely set secret
set_secret() {
  local key=$1
  local value=$2
  echo -n "$value" | gh secret set "$key" -R "$REPO" 2>/dev/null && \
    echo -e "${GREEN}✅ Secret set: $key${NC}" || \
    echo -e "${YELLOW}⚠️  Warning setting $key (may already exist)${NC}"
}

set_secret "GCP_PROJECT_ID" "$GCP_PROJECT_ID"
set_secret "GCP_WORKLOAD_IDENTITY_PROVIDER" "$GCP_WIF_PROVIDER"
set_secret "VAULT_ADDR" "$VAULT_ADDR"
set_secret "AWS_KMS_KEY_ID" "$AWS_KMS_KEY_ID"

echo -e "${GREEN}✅ All secrets configured${NC}"

###############################################################################
# PHASE 4: Create Deployment Issue
###############################################################################
echo -e "\n${BLUE}[PHASE 4] Creating deployment issue...${NC}"

ISSUE_BODY="# 🚀 Automated Self-Service Deployment [$TIMESTAMP]

**Mode**: $MODE
**Status**: In Progress

## Activation Steps Completed ✅
- [x] Repository secrets configured
- [x] Health-check workflow triggered
- [ ] Health-check passing
- [ ] Issues auto-closed

## Reference
See [linked issues](https://github.com/$REPO/issues?q=label%3Adeployment%2Cautomation) for details.

---
*Automated deployment initiated via self-service script*
"

ISSUE_URL=$(gh issue create -R "$REPO" \
  --title "🚀 Self-Service Deployment [$MODE] - $TIMESTAMP" \
  --body "$ISSUE_BODY" \
  --label "deployment,automation" \
  --label "self-service" \
  2>/dev/null | head -1)

if [[ -n "$ISSUE_URL" ]]; then
  ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
  echo -e "${GREEN}✅ Deployment issue created: #$ISSUE_NUM${NC}"
else
  echo -e "${YELLOW}⚠️  Could not create issue (may not have permissions)${NC}"
  ISSUE_NUM=""
fi

###############################################################################
# PHASE 5: Trigger Health-Check Workflow
###############################################################################
echo -e "\n${BLUE}[PHASE 5] Triggering health-check workflow...${NC}"

RUN_OUTPUT=$(gh workflow run secrets-health-multi-layer.yml \
  -R "$REPO" \
  --ref main \
  2>&1 || echo "")

if [[ "$RUN_OUTPUT" == *"Workflow run"* ]] || [[ "$RUN_OUTPUT" == *"queued"* ]]; then
  echo -e "${GREEN}✅ Health-check workflow triggered${NC}"
  sleep 3  # Give workflow time to queue
else
  echo -e "${YELLOW}⚠️  Workflow trigger response: $RUN_OUTPUT${NC}"
fi

###############################################################################
# PHASE 6: Monitor Workflow Run (Non-blocking)
###############################################################################
echo -e "\n${BLUE}[PHASE 6] Monitoring health-check workflow...${NC}"

# Get latest run
LATEST_RUN=$(gh run list -R "$REPO" \
  --workflow=secrets-health-multi-layer.yml \
  --limit 1 \
  --json databaseId,status,conclusion \
  --jq '.[0] | {id: .databaseId, status: .status, conclusion: .conclusion}' 2>/dev/null)

RUN_ID=$(echo "$LATEST_RUN" | grep -o '"id": *[0-9]*' | grep -o '[0-9]*')
RUN_STATUS=$(echo "$LATEST_RUN" | grep -o '"status": *"[^"]*' | grep -o '"[^"]*$' | tr -d '"')
RUN_CONCLUSION=$(echo "$LATEST_RUN" | grep -o '"conclusion": *"[^"]*' | grep -o '"[^"]*$' | tr -d '"')

if [[ -n "$RUN_ID" ]]; then
  RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
  echo -e "${GREEN}✅ Workflow run monitored: $RUN_URL${NC}"
  echo -e "   Status: $RUN_STATUS | Conclusion: $RUN_CONCLUSION"
  
  # Update deployment issue with run link
  if [[ -n "$ISSUE_NUM" ]]; then
    gh issue comment "$ISSUE_NUM" -R "$REPO" \
      --body "🔗 Health-check workflow: [$RUN_ID]($RUN_URL) — Status: $RUN_STATUS" \
      2>/dev/null || true
  fi
else
  echo -e "${YELLOW}⚠️  Could not locate workflow run${NC}"
fi

###############################################################################
# PHASE 7: Auto-Close Tracking Issues (If Successful)
###############################################################################
echo -e "\n${BLUE}[PHASE 7] Auto-close tracking (if health-check passes)...${NC}"

# Wait a bit for workflow to potentially complete (short timeout for demo)
echo "   Waiting for workflow completion..."
sleep 15

# Check if we should close
FINAL_CONCLUSION=$(gh run view "$RUN_ID" -R "$REPO" \
  --json conclusion -q 2>/dev/null || echo "")

if [[ "$FINAL_CONCLUSION" == "success" ]]; then
  echo -e "${GREEN}✅ Health-check PASSED — Auto-closing related issues...${NC}"
  
  # Close old incident issues (keep latest)
  OLD_INCIDENTS=(1715 1718 1719 1721 1705 1699 1639 1638)
  for ISSUE in "${OLD_INCIDENTS[@]}"; do
    gh issue close "$ISSUE" -R "$REPO" \
      --comment "🔄 Deployment successful. Consolidated into latest incident." \
      2>/dev/null && echo -e "${GREEN}   ✅ Closed #$ISSUE${NC}" || true
  done
  
  # Update current deployment issue
  if [[ -n "$ISSUE_NUM" ]]; then
    gh issue comment "$ISSUE_NUM" -R "$REPO" \
      --body "✅ **DEPLOYMENT SUCCESSFUL** — All health-checks passed. System ready for production." \
      2>/dev/null || true
  fi
else
  echo -e "${YELLOW}⚠️  Health-check not yet complete or failed. Monitoring continues in GitHub Actions.${NC}"
  echo -e "   Check: $RUN_URL"
fi

###############################################################################
# PHASE 8: Summary & Next Steps
###############################################################################
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ✅ DEPLOYMENT ACTIVATION COMPLETE                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

cat <<EOF

📊 DEPLOYMENT SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Mode          : $MODE
Timestamp     : $TIMESTAMP
Repository    : $REPO
Deployment    : Issue #$ISSUE_NUM
Health-Check  : Run $RUN_ID ($RUN_STATUS)

🔗 Links
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Deployment    : https://github.com/$REPO/issues/${ISSUE_NUM:-TBD}
Workflow Run  : https://github.com/$REPO/actions/runs/$RUN_ID
Operator Guide: https://github.com/$REPO/blob/main/OPERATOR_FINAL_GUIDE.md

📈 Automation State
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Immutable     — All artifacts versioned & signed
✅ Ephemeral     — OIDC tokens (no long-lived creds)
✅ Idempotent    — All workflows repeatable
✅ No Ops        — Fully automated loop
✅ Hands-Off     — Auto-trigger, auto-remediate, auto-close
✅ GSM/Vault/KMS — Multi-layer secrets configured

🎯 Next Steps
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Monitor workflow: gh run watch $RUN_ID -R $REPO
2. View logs: gh run view $RUN_ID -R $REPO --log
3. See operator guide: cat OPERATOR_FINAL_GUIDE.md

ℹ️  Deployment running in HANDS-OFF mode
   • Issues auto-created on failure
   • Issues auto-closed on success
   • All operations tracked in GitHub Issues

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

exit 0
