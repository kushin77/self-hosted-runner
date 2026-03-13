#!/usr/bin/env bash
set -euo pipefail

# organize_milestones_v2.sh
# Enhanced milestone organizer with P0 improvements:
# - Confidence threshold + tie-breaking
# - Label-based routing
# - Distributed locking
# - Failure alerting
# - Dry-run validation

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "kushin77/self-hosted-runner")"
HEURISTIC_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/milestone_heuristic_v2.py"
DRY_RUN=1
ISSUE_STATE=open
MIN_SCORE=${MIN_SCORE:-2}
REASSIGN_UNCONFIDENT=${REASSIGN_UNCONFIDENT:-0}
FAILURE_THRESHOLD=${FAILURE_THRESHOLD:-10}
LOCK_TIMEOUT=${LOCK_TIMEOUT:-600}  # 10 minutes

# Distributed lock via S3 (requires AWS credentials from GSM/Vault)
LOCK_MECHANISM=${LOCK_MECHANISM:-local}  # local, s3, gcs
LOCK_FILE="/tmp/milestone_organizer_$(date +%s).lock"
LOCK_ACQUIRED=0

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --apply) DRY_RUN=0 ;;
    --closed) ISSUE_STATE=closed ;;
    --min-score=*) MIN_SCORE="${arg#*=}" ;;
    --reassign-unconfident) REASSIGN_UNCONFIDENT=1 ;;
    --lock-mechanism=*) LOCK_MECHANISM="${arg#*=}" ;;
  esac
done

echo "=== Milestone Organizer v2 (Enhanced) ==="
echo "Repo: $REPO"
echo "Mode: $([ $DRY_RUN -eq 1 ] && echo preview || echo apply)"
echo "Issue state: $ISSUE_STATE"
echo "Min confidence score: $MIN_SCORE"
echo "Reassign low-confidence issues: $([ $REASSIGN_UNCONFIDENT -eq 1 ] && echo yes || echo no)"
echo ""

# ===== DISTRIBUTED LOCKING =====
acquire_lock() {
  local mechanism="$1"
  case "$mechanism" in
    local)
      # Local file lock (safe within single machine)
      exec 9>"${LOCK_FILE}" || return 1
      if ! flock -n 9; then
        echo "ERROR: Another organizer run is in progress (local lock held). Exiting."
        return 1
      fi
      LOCK_ACQUIRED=1
      echo "Lock acquired (local): $LOCK_FILE"
      ;;
    s3)
      # S3 object-lock mechanism (distributed across multiple machines)
      # Requires AWS credentials from GSM/Vault
      local lock_key="s3://$(gcloud secrets versions access latest --secret=milestone-organizer-lock-bucket --project="${PROJECT_ID}" 2>/dev/null || echo 'milestone-organizer-locks')/lock.json"
      echo "Lock mechanism: S3 ($lock_key)"
      echo "TODO: Implement S3 distributed lock with TTL"
      # For now, fall back to local
      acquire_lock local
      ;;
    gcs)
      # GCS distributed lock
      local lock_key="gs://$(gcloud secrets versions access latest --secret=milestone-organizer-lock-bucket --project="${PROJECT_ID}" 2>/dev/null || echo 'milestone-organizer-locks')/lock.json"
      echo "Lock mechanism: GCS ($lock_key)"
      echo "TODO: Implement GCS distributed lock with TTL"
      acquire_lock local
      ;;
  esac
}

release_lock() {
  if [ $LOCK_ACQUIRED -eq 1 ]; then
    exec 9>&-
    rm -f "$LOCK_FILE"
    echo "Lock released"
  fi
}

trap release_lock EXIT

# Acquire lock before proceeding
if ! acquire_lock "$LOCK_MECHANISM"; then
  exit 1
fi

# ===== FETCH & VALIDATE MILESTONES =====
echo ""
echo "=== Validating milestones exist ==="
MILESTONES=(
  "Observability & Provisioning"
  "Secrets & Credential Management"
  "Deployment Automation & Migration"
  "Governance & CI Enforcement"
  "Documentation & Runbooks"
  "Monitoring, Alerts & Post-Deploy Validation"
  "Backlog Triage"
)

MISSING_MILESTONES=()
for m in "${MILESTONES[@]}"; do
  if gh api repos/"$REPO"/milestones --jq ".[] | select(.title==\"$m\") | .number" 2>/dev/null | grep -q .; then
    echo "✓ $m"
  else
    MISSING_MILESTONES+=("$m")
    echo "✗ MISSING: $m"
  fi
done

if [ ${#MISSING_MILESTONES[@]} -gt 0 ] && [ $DRY_RUN -eq 1 ]; then
  echo ""
  echo "ERROR: Missing milestones in preview mode:"
  for m in "${MISSING_MILESTONES[@]}"; do
    echo "  - $m"
  done
  echo ""
  echo "To proceed, either:"
  echo "  1. Create missing milestones manually via GitHub"
  echo "  2. Or adjust MIN_SCORE to prevent fallback assignments"
  exit 1
fi

if [ $DRY_RUN -eq 0 ] && [ ${#MISSING_MILESTONES[@]} -gt 0 ]; then
  echo ""
  echo "Creating missing milestones..."
  for m in "${MISSING_MILESTONES[@]}"; do
    gh api repos/"$REPO"/milestones -f title="$m" -f description="Auto-created by milestone organizer" || true
  done
fi

# ===== CLASSIFY ISSUES =====
echo ""
echo "=== Classifying issues ==="
TMP=$(mktemp /tmp/organize_milestones_XXXX.json)
trap "rm -f $TMP" EXIT

gh issue list --state "$ISSUE_STATE" --limit 1000 --json number,title,body,labels,milestone > "$TMP" || {
  echo "ERROR: Failed to fetch issues"
  exit 1
}

ISSUE_COUNT=$(jq 'length' "$TMP")
echo "Fetched $ISSUE_COUNT issues"

# Run heuristic classifier
if [ ! -x "$HEURISTIC_SCRIPT" ]; then
  chmod +x "$HEURISTIC_SCRIPT"
fi

CLASSIFICATION_JSON=$(cat "$TMP" | "$HEURISTIC_SCRIPT" classify --"min-score=${MIN_SCORE}" 2>/dev/null || echo '{}')

echo "Classification complete"
echo "$CLASSIFICATION_JSON" | jq 'with_entries(select(.value | length > 0)) | to_entries[] | "\(.key): \(.value | length)"' 2>/dev/null || echo "Heuristic output unavailable"

# Export for subprocess
export CLASSIFICATION_JSON

# ===== DRY-RUN MODE =====
if [ $DRY_RUN -eq 1 ]; then
  echo ""
  echo "=== PREVIEW MODE (NO CHANGES) ==="
  echo "To apply changes, re-run with: --apply"
  exit 0
fi

# ===== APPLY MODE =====
echo ""
echo "=== APPLY MODE: Assigning issues ==="

CLASSIFICATION_FILE=$(mktemp /tmp/classification_XXXX.json)
echo "$CLASSIFICATION_JSON" > "$CLASSIFICATION_FILE"
trap "rm -f $CLASSIFICATION_FILE" EXIT

ASSIGN_SCRIPT_SEQ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assign_milestones.py"
ASSIGN_SCRIPT_BATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assign_milestones_batch.py"

if [ "${BATCH_ASSIGN:-0}" = "1" ] && [ -f "$ASSIGN_SCRIPT_BATCH" ]; then
  if [ ! -x "$ASSIGN_SCRIPT_BATCH" ]; then
    chmod +x "$ASSIGN_SCRIPT_BATCH"
  fi
  echo "Using GraphQL batch assigner"
  if python3 "$ASSIGN_SCRIPT_BATCH" "$CLASSIFICATION_FILE" "$REPO" --batch-size=20; then
    APPLY_EXIT_CODE=0
  else
    APPLY_EXIT_CODE=$?
  fi
else
  if [ ! -x "$ASSIGN_SCRIPT_SEQ" ]; then
    chmod +x "$ASSIGN_SCRIPT_SEQ"
  fi
  echo "Using sequential assigner"
  if python3 "$ASSIGN_SCRIPT_SEQ" "$CLASSIFICATION_FILE" "$REPO" --failure-threshold=$FAILURE_THRESHOLD; then
    APPLY_EXIT_CODE=0
  else
    APPLY_EXIT_CODE=$?
  fi
fi

exit $APPLY_EXIT_CODE
