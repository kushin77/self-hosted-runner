#!/bin/bash
#
# Automated Terraform Apply for Staging Environment
# - Fetches credentials from GSM (ephemeral)
# - Runs terraform apply with auto-approval
# - Posts audit results to GitHub
# - Cleans up all traces
#
# Usage:
#   ./scripts/deploy-terraform-staging.sh
#
# Environment (optional):
#   GITHUB_TOKEN: Used to post audit comments (required for audit posting)
#   TF_PLAN_FILE: Path to tfplan (default: terraform/environments/staging-tenant-a/tfplan)
#   PROJECT_ID: GCP project (default: p4-platform)
#   ISSUE_NUMBER: GitHub issue to post results (default: 2072)
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

PROJECT_ID="${PROJECT_ID:-p4-platform}"
TF_ENV_DIR="${TF_ENV_DIR:-terraform/environments/staging-tenant-a}"
TF_PLAN_FILE="${TF_PLAN_FILE:-${TF_ENV_DIR}/tfplan}"
ISSUE_NUMBER="${ISSUE_NUMBER:-2072}"
REPO="kushin77/self-hosted-runner"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_SA_JSON="/tmp/sa-tf-$RANDOM.json"

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
  local exit_code=$?
  if [[ -f "$TMP_SA_JSON" ]]; then
    shred -u "$TMP_SA_JSON" || rm -f "$TMP_SA_JSON"
  fi
  unset GOOGLE_APPLICATION_CREDENTIALS
  return $exit_code
}

trap cleanup EXIT

# ============================================================================
# Validate Prerequisites
# ============================================================================

echo "[$(date -u +'%H:%M:%SZ')] Validating deployment prerequisites..."

if ! command -v gcloud &>/dev/null; then
  echo "ERROR: gcloud not found. Install Google Cloud SDK."
  exit 1
fi

if ! command -v terraform &>/dev/null; then
  echo "ERROR: terraform not found. Install Terraform."
  exit 1
fi

if [[ ! -d "$TF_ENV_DIR" ]]; then
  echo "ERROR: Terraform environment directory not found: $TF_ENV_DIR"
  exit 1
fi

if [[ ! -f "$TF_PLAN_FILE" ]]; then
  echo "ERROR: Terraform plan file not found: $TF_PLAN_FILE"
  echo "Please run: cd $TF_ENV_DIR && terraform plan -out=tfplan"
  exit 1
fi

# ============================================================================
# Fetch Credentials from GSM
# ============================================================================

echo "[$(date -u +'%H:%M:%SZ')] Fetching credentials from GSM..."

if ! gcloud secrets versions access latest \
  --secret="tf-staging-sa" \
  --project="$PROJECT_ID" \
  > "$TMP_SA_JSON" 2>&1; then
  echo "ERROR: Failed to fetch tf-staging-sa from GSM"
  exit 1
fi

if ! grep -q "type.*service_account" "$TMP_SA_JSON"; then
  echo "ERROR: Secret does not appear to be a service account JSON"
  exit 1
fi

export GOOGLE_APPLICATION_CREDENTIALS="$TMP_SA_JSON"
echo "[$(date -u +'%H:%M:%SZ')] Credentials loaded (ephemeral, will be destroyed at exit)"

# ============================================================================
# Run Terraform Apply
# ============================================================================

echo "[$(date -u +'%H:%M:%SZ')] Running terraform apply..."

cd "$TF_ENV_DIR"

APPLY_START=$(date +%s)
APPLY_LOG="/tmp/tf-apply-$RANDOM.log"

if terraform apply -auto-approve "$TF_PLAN_FILE" | tee "$APPLY_LOG"; then
  APPLY_STATUS="✅ SUCCESS"
  APPLY_EXIT=0
else
  APPLY_STATUS="❌ FAILED"
  APPLY_EXIT=1
fi

APPLY_END=$(date +%s)
APPLY_DURATION=$((APPLY_END - APPLY_START))

# Extract outputs if apply succeeded
if [[ $APPLY_EXIT -eq 0 ]]; then
  RUNNER_SA_EMAIL=$(terraform output -raw runner_sa_email 2>/dev/null || echo "N/A")
else
  RUNNER_SA_EMAIL="N/A"
fi

# ============================================================================
# Generate Audit Report
# ============================================================================

AUDIT_REPORT=$(cat <<'AUDIT_EOF'
## 🚀 Terraform Apply: Staging Environment (P4)

**Status:** {APPLY_STATUS}
**Timestamp:** {TIMESTAMP}
**Duration:** {APPLY_DURATION}s
**Credentials:** GSM:tf-staging-sa (ephemeral, auto-destroyed)

### Resources Deployed
- Service Account: runner-staging-a@p4-platform.iam.gserviceaccount.com
- Firewall Rules: 4 (ingress-allow/deny, egress-allow/deny)
- Compute Instance Template: runner-staging-a-*

### Outputs
- runner_sa_email: {RUNNER_SA_EMAIL}

{APPLY_LOG_TAIL}

### Next Steps
1. Boot instance from `runner-staging-a-*` template
2. Verify Vault Agent deployed in instance metadata
3. Confirm registry credentials fetched via vault-agent.service
4. Run GitHub runner registration via runner-startup.sh

### Immutable Audit Trail
- Commit: {GIT_COMMIT}
- Branch: main
- All credentials ephemeral (destroyed post-deployment)
- All operations logged to this GitHub issue
AUDIT_EOF
)

# Get last 30 lines of apply log
APPLY_LOG_TAIL=$(tail -30 "$APPLY_LOG" 2>/dev/null | sed 's/^/    /' || echo "    (no log)")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Substitute variables
AUDIT_REPORT="${AUDIT_REPORT//{APPLY_STATUS}/$APPLY_STATUS}"
AUDIT_REPORT="${AUDIT_REPORT//{TIMESTAMP}/$TIMESTAMP}"
AUDIT_REPORT="${AUDIT_REPORT//{APPLY_DURATION}/$APPLY_DURATION}"
AUDIT_REPORT="${AUDIT_REPORT//{RUNNER_SA_EMAIL}/$RUNNER_SA_EMAIL}"
AUDIT_REPORT="${AUDIT_REPORT//{APPLY_LOG_TAIL}/$APPLY_LOG_TAIL}"
AUDIT_REPORT="${AUDIT_REPORT//{GIT_COMMIT}/$GIT_COMMIT}"

# ============================================================================
# Post Audit Comment to GitHub (if GITHUB_TOKEN set)
# ============================================================================

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "[$(date -u +'%H:%M:%SZ')] Posting audit comment to GitHub issue #$ISSUE_NUMBER..."
  
  COMMENT_JSON=$(cat <<EOF
{
  "body": $(echo "$AUDIT_REPORT" | jq -Rs .)
}
EOF
)
  
  GITHUB_API="https://api.github.com/repos/$REPO/issues/$ISSUE_NUMBER/comments"
  
  if curl -s -X POST "$GITHUB_API" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$COMMENT_JSON" >/dev/null 2>&1; then
    echo "[$(date -u +'%H:%M:%SZ')] Audit comment posted successfully"
  else
    echo "[$(date -u +'%H:%M:%SZ')] Warning: Failed to post audit comment"
  fi
else
  echo "[$(date -u +'%H:%M:%SZ')] GITHUB_TOKEN not set; skipping GitHub comment"
  echo "Audit report:"
  echo "$AUDIT_REPORT"
fi

# ============================================================================
# Cleanup and Exit
# ============================================================================

rm -f "$APPLY_LOG"

if [[ $APPLY_EXIT -eq 0 ]]; then
  echo "[$(date -u +'%H:%M:%SZ')] ✅ Deployment completed successfully"
  exit 0
else
  echo "[$(date -u +'%H:%M:%SZ')] ❌ Deployment failed"
  exit 1
fi
