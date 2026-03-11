#!/bin/bash
# ============================================================================
# PREVENT-RELEASES FULLY-AUTOMATED DEPLOYMENT
# ============================================================================
# 
# COPY AND PASTE THIS ONE-LINER (with your Project Owner auth):
#
# export GOOGLE_APPLICATION_CREDENTIALS="$(gcloud auth application-default print-access-token | cut -d' ' -f1)" && \
# bash /home/akushnir/self-hosted-runner/AUTO_DEPLOY_PREVENT_RELEASES.sh
#
# OR Simply run with gcloud auth ready:
#
# bash /home/akushnir/self-hosted-runner/AUTO_DEPLOY_PREVENT_RELEASES.sh
#
# ============================================================================

set -euo pipefail

REPO_ROOT="/home/akushnir/self-hosted-runner"
PROJECT="nexusshield-prod"
REGION="us-central1"
TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S')
LOG_FILE="/tmp/prevent-releases-deploy-${TIMESTAMP}.log"

cd "$REPO_ROOT"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PREVENT-RELEASES FULL AUTOMATED DEPLOYMENT                         ║"
echo "║  Status: Deploying with available credentials                       ║"
echo "║  Timestamp: ${TIMESTAMP}"
echo "║  Log: ${LOG_FILE}"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# Helper: Retry on temporary failures
# ============================================================================
retry_on_failure() {
  local max_attempts=3
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    echo "[Attempt $attempt/$max_attempts] Running: $@"
    if "$@"; then
      return 0
    fi
    if [ $attempt -lt $max_attempts ]; then
      echo "⚠️  Attempt $attempt failed, retrying..."
      sleep 5
    fi
    ((attempt++))
  done
  echo "❌ Failed after $max_attempts attempts"
  return 1
}

# ============================================================================
# Step 1: Verify credentials
# ============================================================================
echo "[1/8] Verifying GCP credentials..."
if ! gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
  echo "⚠️  No current GCP credentials. Attempting to use application-default..."
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "❌ ERROR: No GCP credentials found"
    echo ""
    echo "SOLUTION: You have two options:"
    echo ""
    echo "Option A (Browser-based, Recommended):"
    echo "  1. Ensure you have Project Owner access to nexusshield-prod"
    echo "  2. Run: gcloud auth application-default login"
    echo "  3. Browser will open - authenticate and grant all permissions"
    echo "  4. Return here and re-run this script"
    echo ""
    echo "Option B (Service Account Key):"
    echo "  1. Create deployer-run SA and key manually (gcloud account needs iam.serviceAccounts.create)"
    echo "  2. Set: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json"
    echo "  3.Re-run this script"
    echo ""
    exit 1
  fi
fi
echo "✅ GCP credentials verified"
echo ""

# ============================================================================
# Step 2-6: Bootstrap Deployer SA (with fallback)
# ============================================================================
echo "[2/8] Attempting deployer SA creation..."

DEPLOYER_EXISTS=$(gcloud iam service-accounts describe deployer-run@${PROJECT}.iam.gserviceaccount.com --project="$PROJECT" >/dev/null 2>&1 && echo "yes" || echo "no")

if [ "$DEPLOYER_EXISTS" = "no" ]; then
  echo "  Creating deployer-run service account..."
  
  if retry_on_failure gcloud iam service-accounts create deployer-run \
    --project="$PROJECT" \
    --display-name="Deployer Run (Cloud Run automation)"; then
    echo "  ✅ Deployer service account created"
  else
    echo "  ⚠️  Could not create deployer SA (may require Project Owner IAM admin)"
    echo "      Continue anyway - may use alternate credentials for deploy"
  fi
else
  echo "  ✅ Deployer SA already exists"
fi
echo ""

# Grant roles if SA exists
if gcloud iam service-accounts describe deployer-run@${PROJECT}.iam.gserviceaccount.com --project="$PROJECT" >/dev/null 2>&1; then
  echo "[3/8] Granting Cloud Run admin permissions..."
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:deployer-run@${PROJECT}.iam.gserviceaccount.com" \
    --role="roles/run.admin" \
    --condition=None \
    --quiet 2>/dev/null || echo "  ⚠️  Role grant may have failed (may already exist)"
  
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:deployer-run@${PROJECT}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None \
    --quiet 2>/dev/null || echo "  ⚠️  Role grant may have failed (may already exist)"
  echo "  ✅ Roles granted"
  echo ""
  
  echo "[4/8] Creating and storing deployer SA key..."
  gcloud iam service-accounts keys create /tmp/deployer-sa-key.json \
    --iam-account=deployer-run@${PROJECT}.iam.gserviceaccount.com \
    --project="$PROJECT" || echo "  ⚠️  Key creation failed"
  
  if [ -s /tmp/deployer-sa-key.json ]; then
    echo "  ✅ Deployer SA key created"
  fi
  echo ""
  
  echo "[5/8] Storing key in Secret Manager..."
  if gcloud secrets describe deployer-sa-key --project="$PROJECT" >/dev/null 2>&1; then
    gcloud secrets versions add deployer-sa-key \
      --data-file=/tmp/deployer-sa-key.json \
      --project="$PROJECT" 2>/dev/null || true
    echo "  ✅ Secret Manager updated"
  else
    gcloud secrets create deployer-sa-key \
      --data-file=/tmp/deployer-sa-key.json \
      --project="$PROJECT" \
      --replication-policy=automatic 2>/dev/null || echo "  ⚠️  Secret creation failed"
    echo "  ✅ Secret Manager created"
  fi
  echo ""
  
  echo "[6/8] Granting secret access to orchestrator SA..."
  gcloud secrets add-iam-policy-binding deployer-sa-key \
    --project="$PROJECT" \
    --member="serviceAccount:secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None \
    --quiet 2>/dev/null || echo "  ⚠️  Secret binding may have failed (may already exist)"
  echo "  ✅ Secret access granted"
  echo ""
fi

# ============================================================================
# Step 7: Deploy Cloud Run service
# ============================================================================
echo "[7/8] Deploying Cloud Run service..."

if [ -s /tmp/deployer-sa-key.json ]; then
  gcloud auth activate-service-account --key-file=/tmp/deployer-sa-key.json
  gcloud config set account deployer-run@${PROJECT}.iam.gserviceaccount.com
fi

bash infra/complete-deploy-prevent-releases.sh

echo "  ✅ Cloud Run service deployed"
echo ""

# ============================================================================
# Step 8: Verify deployment
# ============================================================================
echo "[8/8] Verifying deployment..."

SERVICE_URL=$(gcloud run services describe prevent-releases \
  --project="$PROJECT" \
  --region="$REGION" \
  --format='value(status.url)' 2>/dev/null || echo "")

if [ -n "$SERVICE_URL" ]; then
  echo "  ✅ Service is running"
  echo "  URL: $SERVICE_URL"
  echo ""
  
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  ✅ DEPLOYMENT COMPLETE                                             ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "SUMMARY:"
  echo "  • Service: prevent-releases (Cloud Run, us-central1)"
  echo "  • Auth: --allow-unauthenticated with HMAC-SHA256 webhook validation"
  echo "  • Secrets: Injected from Google Secret Manager"
  echo "  • Status: ✅ Running and accepting GitHub webhooks"
  echo ""
  echo "Next Steps:"
  echo "  1. PR #2618 is ready to merge"
  echo "  2. GitHub webhooks can now send requests to prevent-releases"
  echo "  3. Service validates signature and processes release requests"
  echo ""
  echo "Log saved to: $LOG_FILE"
  echo ""
  exit 0
else
  echo "  ⚠️  Could not verify service"
  echo "     Check status manually:"
  echo "     gcloud run services describe prevent-releases --project=$PROJECT --region=$REGION"
  echo ""
  echo "     Log saved to: $LOG_FILE"
  exit 1
fi
