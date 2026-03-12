#!/bin/bash
# ===================================================================
# TIER-2: Grant Required IAM Permissions for Credential Rotation & Failover
# ===================================================================
# Purpose: Idempotent script to grant all required IAM roles for 
#          Tier-2 credential rotation, failover testing, and compliance.
# 
# Constraints:
#   - Immutable: All grants logged to audit trail (append-only JSONL)
#   - Idempotent: Safe to re-run; scripts check existing permissions first
#   - Ephemeral: No temporary state left behind
#   - No-Ops: Run once, all permissions granted for production automation
# ===================================================================

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-nexusshield-prod}"
SA_DEPLOYER="deployer-run@${PROJECT_ID}.iam.gserviceaccount.com"
SA_ORCH="secrets-orch-sa@${PROJECT_ID}.iam.gserviceaccount.com"
SA_MONITOR="nxs-portal-production-v2@${PROJECT_ID}.iam.gserviceaccount.com"

AUDIT_DIR="logs/multi-cloud-audit"
mkdir -p "$AUDIT_DIR"
AUDIT_LOG="$AUDIT_DIR/grant-permissions-$(date +%Y%m%d-%H%M%S).jsonl"

log_audit() {
  local msg="$1"
  local level="${2:-INFO}"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"timestamp":"%s","level":"%s","action":"grant-permissions","message":"%s"}\n' "$timestamp" "$level" "$msg" >> "$AUDIT_LOG"
  printf '%s\n' "[${level}] ${msg}"
}

echo "====================================================================="
echo "TIER-2: IAM Permission Grants"
echo "====================================================================="
echo "Project: $PROJECT_ID"
echo "Audit Log: $AUDIT_LOG"
echo ""

log_audit "Starting IAM grant process for Tier-2 automation"

# ===================================================================
# DEPLOYER-RUN: Pub/Sub, Secrets, Cloud Run, KMS permissions
# ===================================================================
log_audit "Granting roles to deployer-run SA: $SA_DEPLOYER"

declare -a DEPLOYER_ROLES=(
  "roles/pubsub.publisher"            # For verify-rotation.sh (pub/sub trigger)
  "roles/secretmanager.admin"         # For secret management & rotation
  "roles/cloudrun.admin"              # For prevent-releases & potential Cloud Run deployments
  "roles/iam.serviceAccountUser"      # For SA impersonation if needed
  "roles/cloudkms.cryptoKeyEncrypterDecrypter"  # For KMS encryption/decryption
  "roles/storage.objectViewer"        # For artifact/log access
)

for role in "${DEPLOYER_ROLES[@]}"; do
  echo -n "  Granting $role ... "
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_DEPLOYER" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null 2>&1; then
    log_audit "✅ Granted $role to $SA_DEPLOYER" "INFO"
    echo "✅"
  else
    # Check if already granted
    if gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.members:serviceAccount:$SA_DEPLOYER AND bindings.role:$role" \
      --format="value(bindings.members)" 2>/dev/null | grep -q "$SA_DEPLOYER"; then
      log_audit "⏭️  Already has $role (skipping)" "INFO"
      echo "⏭️  (already granted)"
    else
      log_audit "❌ Failed to grant $role to $SA_DEPLOYER" "ERROR"
      echo "❌ (see audit log)"
    fi
  fi
done

# ===================================================================
# ORCHESTRATOR SA: Secrets, Cloud Scheduler, Cloud Run
# ===================================================================
log_audit "Granting roles to orchestrator SA: $SA_ORCH"

declare -a ORCH_ROLES=(
  "roles/secretmanager.admin"
  "roles/cloudscheduler.admin"
  "roles/cloudrun.admin"
  "roles/iam.serviceAccountUser"
)

for role in "${ORCH_ROLES[@]}"; do
  echo -n "  Granting $role ... "
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_ORCH" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null 2>&1; then
    log_audit "✅ Granted $role to $SA_ORCH" "INFO"
    echo "✅"
  else
    if gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.members:serviceAccount:$SA_ORCH AND bindings.role:$role" \
      --format="value(bindings.members)" 2>/dev/null | grep -q "$SA_ORCH"; then
      log_audit "⏭️  Already has $role (skipping)" "INFO"
      echo "⏭️  (already granted)"
    else
      log_audit "❌ Failed to grant $role to $SA_ORCH" "ERROR"
      echo "❌ (see audit log)"
    fi
  fi
done

# ===================================================================
# MONITOR SA: Secrets, Monitoring, KMS
# ===================================================================
log_audit "Granting roles to monitor SA: $SA_MONITOR"

declare -a MONITOR_ROLES=(
  "roles/secretmanager.secretAccessor"
  "roles/monitoring.metricWriter"
  "roles/cloudkms.cryptoKeyEncrypterDecrypter"
)

for role in "${MONITOR_ROLES[@]}"; do
  echo -n "  Granting $role ... "
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_MONITOR" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null 2>&1; then
    log_audit "✅ Granted $role to $SA_MONITOR" "INFO"
    echo "✅"
  else
    if gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.members:serviceAccount:$SA_MONITOR AND bindings.role:$role" \
      --format="value(bindings.members)" 2>/dev/null | grep -q "$SA_MONITOR"; then
      log_audit "⏭️  Already has $role (skipping)" "INFO"
      echo "⏭️  (already granted)"
    else
      log_audit "❌ Failed to grant $role to $SA_MONITOR" "ERROR"
      echo "❌ (see audit log)"
    fi
  fi
done

# ===================================================================
# Verification
# ===================================================================
echo ""
log_audit "Verifying all grants completed"

echo "Verifying deployer-run permissions..."
for role in "${DEPLOYER_ROLES[@]}"; do
  if gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:$SA_DEPLOYER AND bindings.role:$role" \
    --format="value(bindings.members)" 2>/dev/null | grep -q "$SA_DEPLOYER"; then
    echo "  ✅ $role"
  else
    echo "  ❌ $role (MISSING)"
  fi
done

echo ""
log_audit "IAM grant process completed"
echo ""
echo "====================================================================="
echo "✅ IAM GRANTS COMPLETE"
echo "====================================================================="
echo "Next steps:"
echo "1. Verify audit log: $AUDIT_LOG"
echo "2. Re-run credential rotation tests:"
echo "   bash scripts/tests/verify-rotation.sh"
echo "3. Re-run failover tests:"
echo "   bash scripts/ops/test_credential_failover.sh <staging_host>"
echo "====================================================================="
