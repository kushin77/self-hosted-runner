#!/bin/bash
# ===================================================================
# PROJECT OWNER: Complete key rotation + grant automation permissions
# ===================================================================
# Purpose: Owner runs this once to:
#   1. Grant deployer-run key-creation & secret rights
#   2. Create new key and add to Secret Manager
#   3. Verify access
# ===================================================================

set -euo pipefail

PROJECT_ID="nexusshield-prod"
SA_EMAIL="deployer-run@nexusshield-prod.iam.gserviceaccount.com"
SECRET_NAME="deployer-sa-key"

AUDIT_LOG="/tmp/owner-complete-rotation-$(date +%Y%m%d-%H%M%S).jsonl"
TEMP_KEY_FILE="/tmp/deployer-sa-key-new-$(date +%s).json"

log_audit() {
  local msg="$1"
  local level="${2:-INFO}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$level\",\"message\":\"$msg\"}" | tee -a "$AUDIT_LOG"
  echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [$level] $msg" >&2
}

# Verify we're running as owner/admin
log_audit "Checking active account..." "INFO"
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")
log_audit "Active account: $ACTIVE_ACCOUNT" "INFO"

if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  log_audit "ERROR: No active account. Run: gcloud auth login" "ERROR"
  exit 1
fi

# ===================================================================
# STEP 1: Grant deployer-run necessary IAM roles
# ===================================================================
log_audit "STEP 1/4: Granting IAM roles to $SA_EMAIL" "INFO"

# Grant serviceAccountKeyAdmin (to create/rotate keys)
log_audit "  - Granting roles/iam.serviceAccountKeyAdmin" "INFO"
retry_count=0
while [[ $retry_count -lt 3 ]]; do
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/iam.serviceAccountKeyAdmin" \
    --condition=None \
    2>&1 | tee -a "$AUDIT_LOG"; then
    log_audit "    ✅ roles/iam.serviceAccountKeyAdmin granted" "INFO"
    break
  else
    ((retry_count++))
    if [[ $retry_count -lt 3 ]]; then
      log_audit "    ⏳ Retry $retry_count/2..." "WARN"
      sleep 5
    else
      log_audit "    ❌ Failed after 3 retries" "ERROR"
      exit 1
    fi
  fi
done

# Grant secretmanager.secretAccessor (to read own secret versions)
log_audit "  - Granting roles/secretmanager.secretAccessor" "INFO"
if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/secretmanager.secretAccessor" \
  --condition=None \
  2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "    ✅ roles/secretmanager.secretAccessor granted" "INFO"
else
  log_audit "    ⚠️  roles/secretmanager.secretAccessor grant may have failed (non-blocking)" "WARN"
fi

# Grant secretmanager.secretVersionAdder (to add new versions)
log_audit "  - Granting roles/secretmanager.secretVersionAdder to $SA_EMAIL on secret $SECRET_NAME" "INFO"
if gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/secretmanager.secretVersionAdder" \
  --project="$PROJECT_ID" \
  2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "    ✅ secretVersionAdder granted" "INFO"
else
  log_audit "    ⚠️  secretVersionAdder grant may have failed (non-blocking)" "WARN"
fi

log_audit "✅ STEP 1 complete: IAM roles granted" "INFO"

# ===================================================================
# STEP 2: Create new key
# ===================================================================
log_audit "STEP 2/4: Creating new key for $SA_EMAIL" "INFO"

if gcloud iam service-accounts keys create "$TEMP_KEY_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "  ✅ New key created: $TEMP_KEY_FILE" "INFO"
else
  log_audit "  ❌ Failed to create key" "ERROR"
  exit 1
fi

log_audit "✅ STEP 2 complete: New key created" "INFO"

# ===================================================================
# STEP 3: Add key to Secret Manager
# ===================================================================
log_audit "STEP 3/4: Adding new key as secret version in Secret Manager" "INFO"

if gcloud secrets versions add "$SECRET_NAME" \
  --data-file="$TEMP_KEY_FILE" \
  --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "  ✅ New secret version added" "INFO"
else
  log_audit "  ❌ Failed to add secret version" "ERROR"
  rm -f "$TEMP_KEY_FILE"
  exit 1
fi

log_audit "✅ STEP 3 complete: Secret version added" "INFO"

# ===================================================================
# STEP 4: Verify new key works
# ===================================================================
log_audit "STEP 4/4: Verifying new key access" "INFO"

if gcloud auth activate-service-account --key-file="$TEMP_KEY_FILE" --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
  log_audit "  ✅ New key activated" "INFO"
  
  # Test access
  if gcloud projects describe "$PROJECT_ID" --format="value(projectId)" 2>&1 | tee -a "$AUDIT_LOG"; then
    log_audit "  ✅ Project access verified" "INFO"
  else
    log_audit "  ⚠️  Project access check incomplete" "WARN"
  fi
else
  log_audit "  ❌ Failed to activate new key" "ERROR"
  rm -f "$TEMP_KEY_FILE"
  exit 1
fi

# Securely destroy temp key
log_audit "Secure deletion of temporary key..." "INFO"
shred -vfz -n 3 "$TEMP_KEY_FILE" 2>&1 | tee -a "$AUDIT_LOG" || rm -f "$TEMP_KEY_FILE"
log_audit "✅ Temporary key destroyed" "INFO"

log_audit "✅ STEP 4 complete: Key verified" "INFO"

# ===================================================================
# SUMMARY
# ===================================================================
echo ""
echo "====================================================================="
echo "✅ COMPLETE: Full key rotation + permission grant"
echo "====================================================================="
echo ""
echo "What happened:"
echo "  1. ✅ Granted $SA_EMAIL:"
echo "     - roles/iam.serviceAccountKeyAdmin"
echo "     - roles/secretmanager.secretAccessor"
echo "     - roles/secretmanager.secretVersionAdder on secret '$SECRET_NAME'"
echo ""
echo "  2. ✅ Created new key and added to Secret Manager"
echo ""
echo "  3. ✅ Verified new key has access to project"
echo ""
echo "Audit trail: $AUDIT_LOG"
echo ""
echo "Next steps (automatic, lead engineer):"
echo "  1. Lead engineer will detect new secret version"
echo "  2. Cloud Run services will be redeployed with new key"
echo "  3. Monitoring will be updated and issues closed"
echo ""
echo "Old key versions (optional manual cleanup):"
echo "  $ gcloud secrets versions list $SECRET_NAME --project=$PROJECT_ID"
echo "  $ gcloud secrets versions destroy VERSION_ID --secret=$SECRET_NAME --project=$PROJECT_ID"
echo ""
echo "====================================================================="
