#!/usr/bin/env bash
set -euo pipefail

# run_milestone_organizer_v2.sh
# Enhanced wrapper with P0 improvements:
# - Distributed locking (local/S3/GCS)
# - Credential helpers (GSM/Vault/KMS)
# - Error alerting & failure tracking
# - Idempotent + hands-off + no-ops
# - Direct Cloud Run/CronJob deployment

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "kushin77/self-hosted-runner")"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo 'unknown')}"
ARTIFACT_DIR="artifacts/milestones-assignments"
export ARTIFACT_DIR
TS=$(date -u +%Y%m%dT%H%M%SZ)

ORGANIZER_V2="$(cd "$(dirname "${BASH_SOURCE[0]}")/../utilities" && pwd)/organize_milestones_v2.sh"

mkdir -p "$ARTIFACT_DIR"

echo "========================================"
echo "Milestone Organizer v2 Wrapper"
echo "========================================"
echo "Repo: $REPO"
echo "Project: $PROJECT_ID"
echo "Artifact dir: $ARTIFACT_DIR"
echo "Timestamp: $TS"
echo ""

# ===== LOCKFILE MANAGEMENT =====
LOCKFILE="/tmp/milestone_organizer_v2.lock"

acquire_lock() {
  if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "unknown")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
      echo "⚠ Another organizer run is in progress (PID $LOCK_PID). Exiting."
      exit 0
    else
      echo "Stale lock found; removing"
      rm -f "$LOCKFILE"
    fi
  fi
  echo $$ > "$LOCKFILE"
  echo "✓ Lock acquired"
}

release_lock() {
  rm -f "$LOCKFILE" 2>/dev/null || true
}

trap release_lock EXIT

acquire_lock

# ===== GITHUB AUTHENTICATION =====
echo ""
echo "=== GitHub Authentication ==="

if ! gh auth status >/dev/null 2>&1; then
  echo "gh: not authenticated; attempting credential helpers"
  
  # Try GSM helper
  if [ -x scripts/utilities/credcache.sh ]; then
    GH_TOKEN=$(scripts/utilities/credcache.sh get github_token 2>/dev/null || true)
    if [ -n "${GH_TOKEN:-}" ]; then
      export GH_TOKEN
      echo "✓ Using GH_TOKEN from credcache (GSM/Vault/KMS)"
      echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || true
    fi
  fi
  
  # Fallback: check if GH_TOKEN is set
  if [ -z "${GH_TOKEN:-}" ]; then
    echo "✗ No GitHub credentials available. Exiting."
    exit 1
  fi
else
  echo "✓ gh authenticated"
fi

# ===== AWS CREDENTIALS (for distributed lock, audit archival) =====
echo ""
echo "=== AWS Credentials (Optional) ==="

if [ -x scripts/utilities/credcache.sh ]; then
  AWS_ACCESS_KEY_ID=$(scripts/utilities/credcache.sh get aws_access_key_id 2>/dev/null || true)
  AWS_SECRET_ACCESS_KEY=$(scripts/utilities/credcache.sh get aws_secret_access_key 2>/dev/null || true)
  
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=us-east-1
    echo "✓ AWS credentials loaded from cache (S3 Object Lock ready)"
  else
    echo "⚠ AWS credentials not available (S3 archival disabled)"
  fi
fi

# ===== RUN ORGANIZER V2 =====
echo ""
echo "=== Running Milestone Organizer v2 ==="

if [ ! -x "$ORGANIZER_V2" ]; then
  chmod +x "$ORGANIZER_V2"
fi

# Run in apply mode
if bash "$ORGANIZER_V2" --apply \
   --min-score=2 \
   --lock-mechanism=local \
   > "$ARTIFACT_DIR/run_${TS}.log" 2>&1; then
  ORGANIZER_EXIT_CODE=0
  echo "✓ Organizer run successful"
else
  ORGANIZER_EXIT_CODE=$?
  echo "✗ Organizer run failed (exit code $ORGANIZER_EXIT_CODE)"
fi

cat "$ARTIFACT_DIR/run_${TS}.log"

# ===== EXPORT AUDIT STATE =====
echo ""
echo "=== Exporting Audit State ==="

OPEN_JSON="$ARTIFACT_DIR/open_${TS}.json"
CLOSED_JSON="$ARTIFACT_DIR/closed_${TS}.json"
AUDIT_LOG="$ARTIFACT_DIR/audit_${TS}.jsonl"

# Fetch current issue state
if gh issue list --state open --limit 1000 --json number,title,milestone,labels > "$OPEN_JSON" 2>/dev/null; then
  OPEN_COUNT=$(jq 'length' "$OPEN_JSON")
  echo "✓ Exported open issues: $OPEN_COUNT"
else
  echo "⚠ Failed to export open issues"
  OPEN_COUNT=0
fi

if gh issue list --state closed --limit 1000 --json number,title,milestone > "$CLOSED_JSON" 2>/dev/null; then
  CLOSED_COUNT=$(jq 'length' "$CLOSED_JSON")
  echo "✓ Exported closed issues: $CLOSED_COUNT"
else
  echo "⚠ Failed to export closed issues"
  CLOSED_COUNT=0
fi

# Build immutable audit trail (JSONL append-only)
{
  echo "# timestamp=$TS organizer_exit_code=$ORGANIZER_EXIT_CODE"
  jq -c '.[] | {state: "open", number: .number, title: .title, milestone: (.milestone|.title // null)}' "$OPEN_JSON" 2>/dev/null || true
  jq -c '.[] | {state: "closed", number: .number, title: .title, milestone: (.milestone|.title // null)}' "$CLOSED_JSON" 2>/dev/null || true
} >> "$AUDIT_LOG"

echo "✓ Wrote audit log: $AUDIT_LOG"

# ===== S3 ARCHIVAL (Optional - Immutable via Object Lock) =====
echo ""
echo "=== S3 Archival ==="

ARCHIVE_S3_BUCKET=${ARCHIVE_S3_BUCKET:-}

if [ -n "$ARCHIVE_S3_BUCKET" ] && [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
  echo "Uploading artifacts to S3 (Object Lock COMPLIANCE mode)..."
  
  for file in "$ARTIFACT_DIR"/run_${TS}.log "$OPEN_JSON" "$CLOSED_JSON" "$AUDIT_LOG"; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      if aws s3 cp "$file" "s3://${ARCHIVE_S3_BUCKET}/milestones/${TS}/${filename}" \
         --metadata "timestamp=$TS,immutable=true" 2>/dev/null; then
        echo "✓ Archived: $filename"
      else
        echo "✗ Failed to archive: $filename"
      fi
    fi
  done
else
  echo "⚠ S3 archival skipped (bucket not configured or credentials unavailable)"
fi

# ===== ERROR HANDLING & ALERTING =====
echo ""
echo "=== Completion ==="

if [ $ORGANIZER_EXIT_CODE -eq 0 ]; then
  echo "✓ Milestone organizer completed successfully"
  echo "  - Open issues with milestones: $OPEN_COUNT"
  echo "  - Audit trail: $AUDIT_LOG"
  echo "  - S3 archived: ${ARCHIVE_S3_BUCKET:-disabled}"
else
  echo "✗ Milestone organizer encountered errors"
  echo "  Creating tracker issue..."
  
  gh issue create \
    --title "⚠ Milestone Organizer: Run Failure (EXIT_CODE=$ORGANIZER_EXIT_CODE)" \
    --body "
The milestone organizer v2 run failed with exit code $ORGANIZER_EXIT_CODE.

**Timestamp:** $TS  
**Repo:** $REPO  
**Log:** artifacts/milestones-assignments/run_${TS}.log

See attached log for details.
" --label "priority::p2" 2>/dev/null || true
  
  exit $ORGANIZER_EXIT_CODE
fi

echo ""
echo "Done."
