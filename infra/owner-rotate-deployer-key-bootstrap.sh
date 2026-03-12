#!/bin/bash
# ===================================================================
# OWNER-RUN: Rotate deployer-run service account key
# ===================================================================
# Purpose: Project Owner runs this to create a new deployer-run key
#          and add it to Secret Manager. Idempotent and safe to re-run.
# ===================================================================

set -euo pipefail

PROJECT_ID="nexusshield-prod"
SA_EMAIL="deployer-run@nexusshield-prod.iam.gserviceaccount.com"
SECRET_NAME="deployer-sa-key"
TEMP_KEY_FILE="/tmp/deployer-sa-key-new-$(date +%s).json"
# Persistent immutable audit log (append-only JSONL). Local tmp used as fallback.
AUDIT_DIR="logs/multi-cloud-audit"
mkdir -p "$AUDIT_DIR"
AUDIT_LOG="$AUDIT_DIR/owner-rotate-$(date +%Y%m%d-%H%M%S).jsonl"

log_audit() {
  # Temporarily disable nounset inside this helper to avoid failures
  # when parsing/reading optional fields such as prev_hash.
  set +u
  local msg="$1"
  local level="${2:-INFO}"
  local entry
  entry=$(printf "{\"timestamp\":\"%s\",\"level\":\"%s\",\"message\":\"%s\"}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg")

  # Compute chaining: include prev_hash when available
  local prev_line prev_hash hash
  prev_hash=""
  prev_line=""
  if [ -f "$AUDIT_LOG" ] && [ -s "$AUDIT_LOG" ]; then
    prev_line=$(tail -n 1 "$AUDIT_LOG" 2>/dev/null || true)
    if [ -n "$prev_line" ]; then
      # extract hash field if present (best-effort)
      prev_hash=$(printf '%s' "$prev_line" | jq -r '.hash // empty' 2>/dev/null || true)
      # fallback: use sha256 of previous line string
      if [ -z "$prev_hash" ]; then
        prev_hash=$(printf '%s' "$prev_line" | sha256sum | awk '{print $1}')
      fi
    fi
  fi

  hash=$(printf '%s' "$entry" | sha256sum | awk '{print $1}')

  # Best-effort: write entry with hash fields appended
  if printf '%s' "$entry" | jq -c '.' >/dev/null 2>&1; then
    if [ -n "$prev_hash" ]; then
      printf '%s' "$entry" | jq --arg ph "$prev_hash" --arg h "$hash" '. + {prev_hash:$ph, hash:$h}' >>"$AUDIT_LOG"
    else
      printf '%s' "$entry" | jq --arg h "$hash" '. + {hash:$h}' >>"$AUDIT_LOG"
    fi
  else
    # Fallback: raw append with hash metadata
    if [ -n "$prev_hash" ]; then
      printf '%s prev_hash=%s hash=%s\n' "$entry" "$prev_hash" "$hash" >>"$AUDIT_LOG"
    else
      printf '%s hash=%s\n' "$entry" "$hash" >>"$AUDIT_LOG"
    fi
  fi

  # Also write to stdout for operator visibility
  printf '%s\n' "$entry"

  # Restore nounset behavior for the rest of the script
  set -u
}

log_audit "OWNER ROTATION BOOTSTRAP START" "INFO"
log_audit "Project: $PROJECT_ID, SA: $SA_EMAIL" "INFO"

# Step 1: Create a new key for deployer-run
log_audit "Step 1/6: Preflight checks and idempotency" "INFO"

# Idempotency: check last secret version timestamp and skip if rotated recently
MIN_INTERVAL_SECONDS=${MIN_INTERVAL_SECONDS:-600} # 10 minutes default
if gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" --limit=1 --format="value(createTime)" 2>/dev/null | grep -q .; then
  last_create=$(gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" --limit=1 --format="value(createTime)" 2>/dev/null || true)
  if [ -n "$last_create" ]; then
    # convert to epoch
    last_epoch=$(date -d "$last_create" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_create" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    diff=$((now_epoch - last_epoch))
    if [ "$diff" -lt "$MIN_INTERVAL_SECONDS" ]; then
      log_audit "Idempotency: last secret version created ${diff}s ago (< ${MIN_INTERVAL_SECONDS}s). Skipping rotation." "INFO"
      echo "Recent rotation detected (< ${MIN_INTERVAL_SECONDS}s). Exiting successfully." 
      exit 0
    fi
  fi
fi

log_audit "Step 2/6: Creating new key for $SA_EMAIL" "INFO"
if gcloud iam service-accounts keys create "$TEMP_KEY_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  log_audit "✅ New key created: $TEMP_KEY_FILE" "INFO"
else
  log_audit "❌ Failed to create key" "ERROR"
  exit 1
fi

# Step 2: Add new key as a new version in Secret Manager
log_audit "Step 3/6: Ensure Secret Manager secret exists and add version: $SECRET_NAME" "INFO"
# Create secret if it doesn't exist (idempotent)
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  log_audit "Secret $SECRET_NAME not found, creating with automatic replication" "INFO"
  if gcloud secrets create "$SECRET_NAME" --replication-policy="automatic" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log_audit "✅ Secret $SECRET_NAME created" "INFO"
  else
    log_audit "❌ Failed to create secret $SECRET_NAME" "ERROR"
    rm -f "$TEMP_KEY_FILE"
    exit 1
  fi
fi

if gcloud secrets versions add "$SECRET_NAME" \
  --data-file="$TEMP_KEY_FILE" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  log_audit "✅ New secret version added to $SECRET_NAME" "INFO"
else
  log_audit "❌ Failed to add secret version" "ERROR"
  rm -f "$TEMP_KEY_FILE"
  exit 1
fi

# Step 3: Activate the new key locally to verify it works
log_audit "Step 4/6: Verifying new key works (activate & quick health check)" "INFO"
if gcloud auth activate-service-account --key-file="$TEMP_KEY_FILE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  log_audit "✅ New key activated successfully (local verification)" "INFO"
  
  # Quick health check: list project ID
  if gcloud projects describe "$PROJECT_ID" --format="value(projectId)" >/dev/null 2>&1; then
    log_audit "✅ Deployer SA has access to project (verified)" "INFO"
  else
    log_audit "⚠️  Could not verify project access, but key was added" "WARN"
  fi
else
  log_audit "❌ Failed to activate new key (but secret was added)" "ERROR"
  rm -f "$TEMP_KEY_FILE"
  exit 1
fi

# Step 4: Summary and next steps
log_audit "Step 5/6: Rotation complete. Securely deleting local key copy." "INFO"
if command -v shred >/dev/null 2>&1; then
  shred -vfz -n 3 "$TEMP_KEY_FILE" >/dev/null 2>&1 || rm -f "$TEMP_KEY_FILE"
else
  rm -f "$TEMP_KEY_FILE"
fi
log_audit "✅ Temp key securely deleted (best-effort)" "INFO"

# Step 6: Post-rotation summary with recommended cleanup guidance
log_audit "Step 6/6: Post-rotation guidance: list secret versions and retire old keys as appropriate" "INFO"

log_audit "OWNER ROTATION BOOTSTRAP COMPLETE" "INFO"
log_audit "New key version is now in Secret Manager and will be picked up by deployer. This operation is idempotent and safe to re-run." "INFO"

# Print summary
echo ""
echo "====================================================================="
echo "✅ ROTATION COMPLETE (Project Owner)"
echo "====================================================================="
echo "New key version added to Secret Manager: $SECRET_NAME"
echo "Audit log: $AUDIT_LOG"
echo ""
echo "NEXT STEPS (automatic, lead engineer):"
echo "1. Lead engineer will detect new secret version and activate it"
echo "2. Services will restart with the new key"
echo "3. Old key versions can be listed and manually deleted:"
echo "   gcloud secrets versions list $SECRET_NAME --project=$PROJECT_ID"
echo "   gcloud secrets versions destroy VERSION_ID --secret=$SECRET_NAME --project=$PROJECT_ID"
echo "====================================================================="
