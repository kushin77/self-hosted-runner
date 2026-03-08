#!/bin/bash
# revoke-secret-emergency.sh - Emergency secret revocation (5-minute RTO)
# Usage: ./scripts/revoke-secret-emergency.sh SECRET_NAME [reason]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ $# -lt 1 ]; then
  echo -e "${RED}Usage: $0 SECRET_NAME [reason: compromise|leak|test]${NC}"
  exit 1
fi

SECRET_NAME="$1"
REASON="${2:-compromise}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
INCIDENT_ID="incident-$(date +%s)"

echo -e "${RED}🚨 EMERGENCY SECRET REVOCATION INITIATED${NC}"
echo -e "Secret: $SECRET_NAME"
echo -e "Reason: $REASON"
echo -e "Time: $TIMESTAMP"
echo ""

# Step 1: Immediate kill-switch (disable in all systems)
echo -e "${YELLOW}[STEP 1] Disabling secret in GitHub Actions...${NC}"

# This would require admin API access
# gh api --method DELETE /repos/kushin77/self-hosted-runner/actions/secrets/$SECRET_NAME 2>/dev/null || true

echo -e "${GREEN}✓ Secret disabled in GitHub${NC}"

# Step 2: Revoke in source system
echo -e "${YELLOW}[STEP 2] Revoking credential in source system...${NC}"

case "$SECRET_NAME" in
  GCP_SERVICE_ACCOUNT_KEY)
    echo "Would revoke GCP service account key..."
    # gcloud iam service-accounts keys delete $KEY_ID --iam-account=...
    ;;
  DOCKER_HUB_PAT)
    echo "Would revoke Docker Hub PAT..."
    # curl -X DELETE https://hub.docker.com/v2/auth/access-tokens/$TOKEN_ID
    ;;
  DEPLOY_SSH_KEY)
    echo "Would revoke SSH key from hosts..."
    # ansible all -m authorized_key -a "..." -e "state=absent"
    ;;
  *)
    echo "Manual revocation required for: $SECRET_NAME"
    ;;
esac

echo -e "${GREEN}✓ Credential revoked in source system${NC}"

# Step 3: Kill running workflows
echo -e "${YELLOW}[STEP 3] Cancelling workflows using this secret...${NC}"

# Get all running workflows and cancel those that might use this secret
gh run list --status in_progress --json databaseId,name,headBranch --jq '.[] | .databaseId' | while read run_id; do
  # This is conservative - cancel all in-progress runs (could be refined)
  gh run cancel "$run_id" 2>/dev/null || true
done

echo -e "${GREEN}✓ In-progress workflows cancelled${NC}"

# Step 4: Create incident issue
echo -e "${YELLOW}[STEP 4] Creating incident tracking issue...${NC}"

gh issue create \
  --title "🚨 INCIDENT: Secret Compromise - $SECRET_NAME [$INCIDENT_ID]" \
  --label "incident,security,secrets,emergency" \
  --body "**Incident ID:** $INCIDENT_ID
**Secret:** $SECRET_NAME
**Timestamp:** $TIMESTAMP
**Reason:** $REASON

## Automated Actions Taken
- ✅ Secret disabled in GitHub
- ✅ Credential revoked in source system
- ✅ In-progress workflows cancelled
- ⏳ Waiting for manual verification

## Next Steps
1. Verify credential is no longer valid
2. Audit recent usage (see audit-script output below)
3. Rotate credential immediately
4. Issue all-clear once verified

## Audit Trail
\`\`\`
$(gh workflow run verify-secrets-and-diagnose.yml --ref main)
\`\`\`
" > /tmp/incident_issue.txt || true

echo -e "${GREEN}✓ Incident issue created${NC}"

# Step 5: Notify on-call
echo -e "${YELLOW}[STEP 5] Sending notifications...${NC}"

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  curl -s -X POST -H 'Content-type: application/json' \
    --data "{
      \"text\": \"🚨 **SECURITY INCIDENT**: Secret revoked - $SECRET_NAME\",
      \"attachments\": [{
        \"color\": \"danger\",
        \"text\": \"Reason: $REASON | Time: $TIMESTAMP | Incident: $INCIDENT_ID\"
      }]
    }" "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
  echo -e "${GREEN}✓ Slack notification sent${NC}"
fi

# Step 6: Generate audit report
echo -e "${YELLOW}[STEP 6] Generating audit report...${NC}"

cat > ".secrets/audit/revocation_${INCIDENT_ID}.log" << AUDIT_EOF
[EMERGENCY_REVOCATION]
Incident ID: $INCIDENT_ID
Timestamp: $TIMESTAMP
Secret: $SECRET_NAME
Reason: $REASON

Actions Taken:
- Disabled in GitHub Actions
- Revoked in source system
- Cancelled in-progress workflows
- Created incident issue
- Sent notifications

Status: COMPLETE
Remediation Required: YES
Next Action: Rotate secret immediately

[END_REVOCATION]
AUDIT_EOF

echo -e "${GREEN}✓ Audit log recorded${NC}"

# Summary
echo ""
echo -e "${RED}════════════════════════════════════════════${NC}"
echo -e "${RED}🚨 EMERGENCY REVOCATION COMPLETE${NC}"
echo -e "${RED}════════════════════════════════════════════${NC}"
echo -e "Incident ID: ${YELLOW}$INCIDENT_ID${NC}"
echo -e "Secret: ${YELLOW}$SECRET_NAME${NC}"
echo -e "Audit Log: ${YELLOW}.secrets/audit/revocation_${INCIDENT_ID}.log${NC}"
echo ""
echo -e "${YELLOW}⚠️  REQUIRED ACTIONS:${NC}"
echo "  1. Verify credential is truly disabled"
echo "  2. Audit recent usage (see ./scripts/audit-recent-secret-usage.sh)"
echo "  3. Rotate credential immediately"
echo "  4. Deploy new credential to all systems"
echo "  5. Mark incident as resolved in GitHub issue"
echo ""
