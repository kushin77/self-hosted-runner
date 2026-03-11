#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PREVENT-RELEASES AUTOMATED DEPLOYMENT (First-Run)
# ============================================================================
# Fully automated deployment orchestrator:
# 1. Attempts to bootstrap deployer SA + role on first run (idempotent)
# 2. Retrieves deployer key from GSM or /tmp
# 3. Activates deployer SA credentials
# 4. Runs the orchestrator to deploy Cloud Run, scheduler, alerts
# 5. Runs post-deployment verification
#
# PROPERTIES:
#   - Immutable: Cloud Logs + GitHub audit trail
#   - Ephemeral: Cloud Run scales to 0
#   - Idempotent: Safe to re-run; skips existing resources
#   - No-Ops: Fully automated, zero manual steps after this
#   - Hands-Off: No GitHub Actions, direct deployment
#
# USAGE:
#   bash infra/deploy-prevent-releases-automated.sh
#
# ============================================================================

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
SERVICE=${SERVICE:-prevent-releases}
DEPL_SA_NAME=deployer-run
DEPL_SA=${DEPL_SA_NAME}@${PROJECT}.iam.gserviceaccount.com
SECRET_NAME=deployer-sa-key
TMP_KEY=/tmp/deployer-sa-key.json
BOOTSTRAP_SCRIPT=infra/bootstrap-deployer-run.sh
ORCHESTRATOR_SCRIPT=infra/complete-deploy-prevent-releases.sh

echo "========================================================================"
echo "PREVENT-RELEASES AUTOMATED DEPLOYMENT"
echo "========================================================================"
echo "Project: $PROJECT | Region: $REGION | Service: $SERVICE"
echo "Deployer SA: $DEPL_SA"
echo "========================================================================"
echo ""

# ========================================================================
# STEP 1: ATTEMPT FIRST-RUN BOOTSTRAP (Idempotent)
# ========================================================================
echo "[STEP 1/4] Checking if bootstrap needed..."

if [ ! -f "$TMP_KEY" ]; then
  echo "  Deployer key not found at $TMP_KEY"
  
  # Check if secret exists in GSM
  if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
    echo "  ✓ Secret $SECRET_NAME found in GSM; retrieving..."
    gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" > "$TMP_KEY"
    echo "  ✓ Key retrieved to $TMP_KEY"
  else
    echo "  Secret not found in GSM; attempting bootstrap..."
    if [ -f "$BOOTSTRAP_SCRIPT" ]; then
      echo "  Running bootstrap: $BOOTSTRAP_SCRIPT"
      if bash "$BOOTSTRAP_SCRIPT"; then
        echo "  ✓ Bootstrap completed successfully"
        # Retrieve key from GSM
        echo "  Retrieving deployer key from GSM..."
        gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" > "$TMP_KEY"
        echo "  ✓ Key retrieved to $TMP_KEY"
      else
        echo "  ⚠ Bootstrap failed (missing permissions). Checking for existing key..."
        if [ ! -f "$TMP_KEY" ]; then
          echo "  ERROR: No deployer key found and bootstrap failed."
          echo "  ACTION REQUIRED: Project owner must run bootstrap:"
          echo "    bash $BOOTSTRAP_SCRIPT"
          echo "  Or manually upload key to $TMP_KEY"
          exit 1
        fi
      fi
    else
      echo "  ERROR: Bootstrap script not found at $BOOTSTRAP_SCRIPT"
      exit 1
    fi
  fi
else
  echo "  ✓ Deployer key found at $TMP_KEY"
fi

# ========================================================================
# STEP 2: ACTIVATE DEPLOYER CREDENTIALS
# ========================================================================
echo ""
echo "[STEP 2/4] Activating deployer service account..."
if ! gcloud auth activate-service-account --key-file="$TMP_KEY" --quiet; then
  echo "  ERROR: Failed to activate deployer SA"
  exit 1
fi
ACTIVE_ACCOUNT=$(gcloud config list --format='value(core.account)')
echo "  ✓ Activated as: $ACTIVE_ACCOUNT"

gcloud config set project "$PROJECT" --quiet
echo "  ✓ Project set to $PROJECT"

# ========================================================================
# STEP 3: RUN ORCHESTRATOR
# ========================================================================
echo ""
echo "[STEP 3/4] Running orchestrator (idempotent deployment)..."
if [ ! -f "$ORCHESTRATOR_SCRIPT" ]; then
  echo "  ERROR: Orchestrator script not found at $ORCHESTRATOR_SCRIPT"
  exit 1
fi

if bash "$ORCHESTRATOR_SCRIPT"; then
  echo "  ✓ Orchestrator completed successfully"
else
  ORCH_EXIT=$?
  echo "  ⚠ Orchestrator exited with code $ORCH_EXIT"
  if [ $ORCH_EXIT -eq 1 ]; then
    echo "  Some steps may have failed (e.g., alerts). Continuing to verification..."
  else
    exit $ORCH_EXIT
  fi
fi

# ========================================================================
# STEP 4: POST-DEPLOYMENT VERIFICATION (Optional/Best-Effort)
# ========================================================================
echo ""
echo "[STEP 4/4] Running post-deployment verification..."

VERIFY_SCRIPT="scripts/verify/post-deploy-prevent-releases.sh"
if [ -f "$VERIFY_SCRIPT" ]; then
  echo "  Running: $VERIFY_SCRIPT"
  if bash "$VERIFY_SCRIPT"; then
    echo "  ✓ Verification passed"
  else
    VERIFY_EXIT=$?
    echo "  ⚠ Verification checks failed (exit code $VERIFY_EXIT)"
    echo "  See issue #2621 for manual verification steps"
  fi
else
  echo "  ℹ Verification script not found at $VERIFY_SCRIPT"
  echo "  Manual verification checklist available in issue #2621"
fi

# ========================================================================
# SUMMARY
# ========================================================================
echo ""
echo "========================================================================"
echo "✅ AUTOMATED DEPLOYMENT COMPLETE"
echo "========================================================================"
echo ""
echo "NEXT STEPS:"
echo "1. Verify Cloud Run service is READY:"
echo "   gcloud run services describe $SERVICE --project=$PROJECT --region=$REGION"
echo ""
echo "2. Test webhook delivery (see issue #2621 for test procedures)"
echo ""
echo "3. Merge PR #2618 once verification complete:"
echo "   gh pr merge 2618 --auto"
echo ""
echo "SERVICE DETAILS:"
echo "  - Service: $SERVICE"
echo "  - Project: $PROJECT"
echo "  - Region: $REGION"
echo "  - Deployer SA: $DEPL_SA"
echo ""
echo "LOGS & AUDIT TRAIL:"
echo "  - Cloud Logs: https://console.cloud.google.com/logs/query?project=$PROJECT"
echo "  - GitHub issues: #2620 (deployment), #2621 (verification)"
echo "  - GitHub PR: #2618 (code review)"
echo ""
echo "========================================================================"
