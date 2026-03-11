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
AUDIT_LOG="/tmp/owner-rotate-audit-$(date +%Y%m%d-%H%M%S).jsonl"

log_audit() {
  local msg="$1"
  local level="${2:-INFO}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$level\",\"message\":\"$msg\"}" | tee -a "$AUDIT_LOG"
}

log_audit "OWNER ROTATION BOOTSTRAP START" "INFO"
log_audit "Project: $PROJECT_ID, SA: $SA_EMAIL" "INFO"

# Step 1: Create a new key for deployer-run
log_audit "Step 1/4: Creating new key for $SA_EMAIL" "INFO"
if gcloud iam service-accounts keys create "$TEMP_KEY_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "✅ New key created: $TEMP_KEY_FILE" "INFO"
else
  log_audit "❌ Failed to create key" "ERROR"
  exit 1
fi

# Step 2: Add new key as a new version in Secret Manager
log_audit "Step 2/4: Adding key to Secret Manager secret: $SECRET_NAME" "INFO"
if gcloud secrets versions add "$SECRET_NAME" \
  --data-file="$TEMP_KEY_FILE" \
  --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "✅ New secret version added" "INFO"
else
  log_audit "❌ Failed to add secret version" "ERROR"
  rm -f "$TEMP_KEY_FILE"
  exit 1
fi

# Step 3: Activate the new key locally to verify it works
log_audit "Step 3/4: Verifying new key works (activate & list projects)" "INFO"
if gcloud auth activate-service-account --key-file="$TEMP_KEY_FILE" --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "✅ New key activated successfully" "INFO"
  
  # Quick health check
  if gcloud projects describe "$PROJECT_ID" --format="value(projectId)" 2>&1 | tee -a "$AUDIT_LOG"; then
    log_audit "✅ Deployer SA has access to project (verified)" "INFO"
  else
    log_audit "⚠️  Could not verify project access, but key was added" "WARN"
  fi
else
  log_audit "❌ Failed to activate new key" "ERROR"
  rm -f "$TEMP_KEY_FILE"
  exit 1
fi

# Step 4: Summary and next steps
log_audit "Step 4/4: Rotation complete. Cleaning up local key copy." "INFO"
shred -vfz -n 3 "$TEMP_KEY_FILE" 2>&1 | tee -a "$AUDIT_LOG" || rm -f "$TEMP_KEY_FILE"
log_audit "✅ Temp key securely deleted" "INFO"

log_audit "OWNER ROTATION BOOTSTRAP COMPLETE" "INFO"
log_audit "New key version is now in Secret Manager and will be picked up by deployer." "INFO"

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
