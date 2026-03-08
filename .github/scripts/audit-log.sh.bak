#!/bin/bash

# ============================================================================
# .github/scripts/audit-log.sh
# Global Audit Logging for CI/CD Governance
# 
# Purpose: Log all infrastructure changes, deployments, and sensitive
#          operations to a centralized audit trail
# 
# Usage:  
#   audit-log.sh --action <action> --workflow <name> --status <success|failure>
#   
# Examples:
#   audit-log.sh --action deploy_start --workflow "terraform-apply-prod" --run-id 123456
#   audit-log.sh --action deploy_end --status success --run-id 123456
#   audit-log.sh --action credential_rotation --resource "aws-prod" --duration 45
#
# Audit destinations: CloudWatch, S3, GitHub Issues (for incidents)
# ============================================================================

set -euo pipefail

# Configuration
AUDIT_TABLE="cicd-governance-audit"
AUDIT_LOG_GROUP="/aws/governance/audit"
AUDIT_S3_BUCKET="audit-logs-$(echo $GITHUB_REPOSITORY | sed 's/\//-/g')"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
ACTION=""
WORKFLOW="${GITHUB_WORKFLOW:-unknown}"
STATUS=""
RESOURCE=""
ACTOR="${GITHUB_ACTOR:-ci-bot}"
RUN_ID="${GITHUB_RUN_ID:-}"
REF="${GITHUB_REF:-}"
SEVERITY="info"
CHANGES=""
APPROVAL=""
DETAILS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --action)
      ACTION="$2"
      shift 2
      ;;
    --workflow)
      WORKFLOW="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
      shift 2
      ;;
    --resource)
      RESOURCE="$2"
      shift 2
      ;;
    --actor)
      ACTOR="$2"
      shift 2
      ;;
    --severity)
      SEVERITY="$2"
      shift 2
      ;;
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --changes)
      CHANGES="$2"
      shift 2
      ;;
    --approval)
      APPROVAL="$2"
      shift 2
      ;;
    --details)
      DETAILS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required fields
if [ -z "$ACTION" ]; then
  echo -e "${RED}❌ Error: --action is required${NC}"
  exit 1
fi

# Build audit record JSON
read -r -d '' AUDIT_RECORD << EOF || true
{
  "timestamp": "$TIMESTAMP",
  "workflow": "$WORKFLOW",
  "action": "$ACTION",
  "actor": "$ACTOR",
  "status": "$STATUS",
  "resource": "$RESOURCE",
  "run_id": "$RUN_ID",
  "ref": "$REF",
  "severity": "$SEVERITY",
  "changes": "$CHANGES",
  "approval": "$APPROVAL",
  "details": "$DETAILS"
}
EOF

echo -e "${GREEN}📝 Audit Record:${NC}"
echo "$AUDIT_RECORD" | jq .

# Write to local audit log (for later export)
mkdir -p /tmp/audit-logs
echo "$AUDIT_RECORD" >> "/tmp/audit-logs/${RUN_ID:-local}.jsonl"

# Attempt to write to AWS CloudWatch (if credentials available)
if command -v aws &> /dev/null; then
  if [ -n "${AWS_REGION:-}" ]; then
    echo -e "${YELLOW}📤 Uploading to CloudWatch...${NC}"
    aws logs put-log-events \
      --log-group-name "$AUDIT_LOG_GROUP" \
      --log-stream-name "$(date +%Y/%m/%d)" \
      --log-events timestamp=$(date +%s),message="$AUDIT_RECORD" \
      2>/dev/null || echo -e "${YELLOW}⚠️  CloudWatch upload skipped (credentials unavailable)${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  AWS CLI not available; skipping CloudWatch upload${NC}"
fi

# Archive to local file for GitHub Actions artifact export
ARCHIVE_PATH=".github/audit-logs/archive-${TIMESTAMP// /T}.jsonl"
mkdir -p ".github/audit-logs"
echo "$AUDIT_RECORD" >> "$ARCHIVE_PATH"

# For critical violations, create GitHub issue
if [ "$SEVERITY" = "critical" ]; then
  echo -e "${RED}🚨 CRITICAL EVENT - Creating GitHub issue${NC}"
  
  ISSUE_TITLE="🚨 Governance Violation: $ACTION"
  ISSUE_BODY="**Timestamp:** $TIMESTAMP  
**Workflow:** $WORKFLOW  
**Actor:** $ACTOR  
**Resource:** $RESOURCE  
**Status:** $STATUS  
**Run:** [#$RUN_ID](https://github.com/$GITHUB_REPOSITORY/actions/runs/$RUN_ID)  

\`\`\`json
$AUDIT_RECORD
\`\`\`

**Action Required:** Review and remediate immediately."
  
  # Only create issue if GH_TOKEN available
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    gh issue create \
      --title "$ISSUE_TITLE" \
      --body "$ISSUE_BODY" \
      --label "governance-critical,incident" \
      || echo "⚠️  Could not create issue (permissions may be limited)"
  fi
fi

# Log to GitHub Actions step summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" << EOF

### 📝 Audit Log Entry
- **Action:** $ACTION
- **Workflow:** $WORKFLOW
- **Status:** $STATUS
- **Timestamp:** $TIMESTAMP
- **Actor:** $ACTOR
- **Severity:** $SEVERITY

EOF
fi

echo -e "${GREEN}✅ Audit log recorded${NC}"
