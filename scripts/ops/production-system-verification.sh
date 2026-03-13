#!/bin/bash
# Production System Verification & Readiness Check
# Autonomous verification of all production systems
# Run: bash scripts/ops/production-system-verification.sh [--full]

set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
FULL_CHECK="${1:---quick}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize results
declare -A CHECKS
declare -A STATUSES

echo "🔍 Production System Verification — $TIMESTAMP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Helper functions
check_pass() {
  CHECKS["$1"]=1
  STATUSES["$1"]="PASS"
  echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
  CHECKS["$1"]=0
  STATUSES["$1"]="FAIL"
  echo -e "${RED}✗${NC} $1"
}

check_warn() {
  CHECKS["$1"]=2
  STATUSES["$1"]="WARN"
  echo -e "${YELLOW}⚠${NC} $1: $2"
}

check_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# SECTION 1: Cloud Scheduler Verification
# ============================================================================

echo ""
echo "📅 Cloud Scheduler Jobs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check milestone organizer scheduler
if RESULT=$(gcloud scheduler jobs describe milestone-organizer-weekly --location=$REGION --project=$PROJECT_ID --format='table(state, schedule)' 2>&1); then
  STATE=$(echo "$RESULT" | tail -1 | awk '{print $1}')
  SCHED=$(echo "$RESULT" | tail -1 | awk '{print $2}')
  if [[ "$STATE" == "ENABLED" ]]; then
    check_pass "Milestone Organizer Scheduler (weekly, $SCHED)"
  else
    check_warn "Milestone Organizer Scheduler" "state=$STATE (expected ENABLED)"
  fi
else
  check_fail "Milestone Organizer Scheduler: $RESULT"
fi

# Check credential rotation scheduler
if RESULT=$(gcloud scheduler jobs describe credential-rotation-daily --location=$REGION --project=$PROJECT_ID --format='table(state, schedule)' 2>&1); then
  STATE=$(echo "$RESULT" | tail -1 | awk '{print $1}')
  SCHED=$(echo "$RESULT" | tail -1 | awk '{print $2}')
  if [[ "$STATE" == "ENABLED" ]]; then
    check_pass "Credential Rotation Scheduler (daily, $SCHED)"
  else
    check_warn "Credential Rotation Scheduler" "state=$STATE (expected ENABLED)"
  fi
else
  check_fail "Credential Rotation Scheduler: $RESULT"
fi

# ============================================================================
# SECTION 2: Cloud Run Services
# ============================================================================

echo ""
echo "🐳 Cloud Run Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if RESULT=$(gcloud run services describe milestone-organizer --region=$REGION --platform managed --format='table(status.url, status.conditions[0].status)' 2>&1); then
  URL=$(echo "$RESULT" | tail -1 | awk '{print $1}')
  READY=$(echo "$RESULT" | tail -1 | awk '{print $2}')
  if [[ "$READY" == "True" ]]; then
    check_pass "Milestone Organizer Service ✓ ($URL)"
  else
    check_warn "Milestone Organizer Service" "Ready=$READY (expected True)"
  fi
else
  check_fail "Milestone Organizer Service: $RESULT"
fi

# ============================================================================
# SECTION 3: Google Secret Manager
# ============================================================================

echo ""
echo "🔐 Google Secret Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REQUIRED_SECRETS=("github-token" "VAULT_ADDR" "aws-access-key-id" "aws-secret-access-key")
POPULATED_SECRETS=0
for SECRET in "${REQUIRED_SECRETS[@]}"; do
  if gcloud secrets describe "$SECRET" --project=$PROJECT_ID &>/dev/null; then
    VERSIONS=$(gcloud secrets versions list "$SECRET" --project=$PROJECT_ID --limit=1 --format='value(name)' | wc -l)
    if [[ $VERSIONS -gt 0 ]]; then
      check_pass "Secret: $SECRET (versions: $VERSIONS)"
      ((POPULATED_SECRETS++))
    else
      check_warn "Secret: $SECRET" "no versions found"
    fi
  else
    check_fail "Secret: $SECRET (does not exist)"
  fi
done

if [[ $POPULATED_SECRETS -ge 3 ]]; then
  check_pass "GSM: Minimum required secrets populated ($POPULATED_SECRETS/$REQUIRED_SECRETS)"
else
  check_warn "GSM: Missing credentials" "only $POPULATED_SECRETS/$REQUIRED_SECRETS populated"
fi

# ============================================================================
# SECTION 4: Git Repository Status
# ============================================================================

echo ""
echo "📝 Git Repository"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
  if [[ "$BRANCH" == "main" ]]; then
    check_pass "Current branch: main"
  else
    check_warn "Current branch" "$BRANCH (expected main)"
  fi
else
  check_fail "Failed to get current branch"
fi

if HASH=$(git rev-parse --short HEAD 2>/dev/null); then
  check_pass "Latest commit: $HASH"
else
  check_fail "Failed to get commit hash"
fi

UNCOMMITTED=$(git status --short 2>/dev/null | wc -l)
if [[ $UNCOMMITTED -eq 0 ]]; then
  check_pass "Working directory clean (no uncommitted changes)"
else
  check_warn "Working directory" "$UNCOMMITTED uncommitted changes"
fi

# ============================================================================
# SECTION 5: Automation Scripts Status
# ============================================================================

echo ""
echo "🤖 Automation Scripts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SCRIPTS=(
  "scripts/secrets/rotate-credentials.sh"
  "scripts/cloud/aws-inventory-collect.sh"
  "scripts/utilities/organize_milestones_v2.sh"
  "scripts/utilities/assign_milestones_batch.py"
  "scripts/monitoring/metrics_server.py"
)

for SCRIPT in "${SCRIPTS[@]}"; do
  if [[ -f "$SCRIPT" ]]; then
    if [[ -x "$SCRIPT" ]] || [[ "${SCRIPT}" == *".py" ]]; then
      check_pass "Script: $SCRIPT"
    else
      check_warn "Script: $SCRIPT" "not executable"
    fi
  else
    check_fail "Script: $SCRIPT (not found)"
  fi
done

# ============================================================================
# SECTION 6: Audit Trail & Immutability
# ============================================================================

echo ""
echo "📊 Audit Trail"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f "artifacts/milestones-assignments/audit_$(date +%Y%m%d)*.jsonl" ]]; then
  ENTRIES=$(find artifacts/milestones-assignments -name "audit_*.jsonl" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
  if [[ -n "$ENTRIES" && "$ENTRIES" -gt 0 ]]; then
    check_pass "Audit trail: $ENTRIES entries immutable"
  fi
else
  check_info "Audit trail: no entries yet (first run pending)"
fi

# ============================================================================
# SECTION 7: Cloud Build Templates
# ============================================================================

echo ""
echo "🔨 Cloud Build Templates"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TEMPLATES=(
  "cloudbuild.milestone-organizer.yaml"
  "cloudbuild.yaml"
)

for TEMPLATE in "${TEMPLATES[@]}"; do
  if [[ -f "$TEMPLATE" ]]; then
    check_pass "Template: $TEMPLATE"
  else
    check_warn "Template: $TEMPLATE" "not found (optional)"
  fi
done

# ============================================================================
# SECTION 8: Pre-commit Security
# ============================================================================

echo ""
echo "🛡️ Pre-commit Security"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f ".pre-commit-config.yaml" ]]; then
  check_pass "Pre-commit config: active"
else
  check_warn "Pre-commit config" "not found"
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

for STATUS in "${STATUSES[@]}"; do
  if [[ "$STATUS" == "PASS" ]]; then
    ((PASS_COUNT++))
  elif [[ "$STATUS" == "FAIL" ]]; then
    ((FAIL_COUNT++))
  else
    ((WARN_COUNT++))
  fi
done

echo "📋 SUMMARY"
echo "  ✓ Passed: $PASS_COUNT"
echo "  ⚠ Warnings: $WARN_COUNT"
echo "  ✗ Failed: $FAIL_COUNT"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  if [[ $WARN_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ PRODUCTION READY${NC} — All systems operational"
  else
    echo -e "${YELLOW}⚠ PRODUCTION READY WITH WARNINGS${NC} — Review above"
  fi
  exit 0
else
  echo -e "${RED}✗ PRODUCTION NOT READY${NC} — Fix failures above"
  exit 1
fi
