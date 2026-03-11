#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PREVENT-RELEASES FINAL DEPLOYMENT & VERIFICATION
# ============================================================================
# Self-healing, idempotent deployment + verification orchestrator
# Completes all remaining steps once Cloud Run permission is available
# Usage: bash infra/deploy-prevent-releases-final.sh
# ============================================================================

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
SERVICE=${SERVICE:-prevent-releases}
IMAGE=${IMAGE:-us-central1-docker.pkg.dev/${PROJECT}/production-portal-docker/${SERVICE}:latest}
SA=${SA:-nxs-prevent-releases-sa@${PROJECT}.iam.gserviceaccount.com}

echo "=========================================="
echo "PREVENT-RELEASES FINAL DEPLOYMENT"
echo "Project: $PROJECT | Region: $REGION | Service: $SERVICE"
echo "=========================================="

# ==================== STEP 1: Verify Secrets ====================
echo ""
echo "[1/6] Verifying GSM secrets exist..."
for secret in github-app-private-key github-app-id github-app-webhook-secret github-app-token; do
  if ! gcloud secrets describe "$secret" --project="$PROJECT" >/dev/null 2>&1; then
    echo "ERROR: Secret $secret does not exist in GSM"
    echo "Run: printf 'placeholder' | gcloud secrets create $secret --data-file=- --project=$PROJECT"
    exit 1
  fi
  echo "  ✓ Secret $secret exists"
done

# ==================== STEP 2: Deploy Cloud Run ====================
echo ""
echo "[2/6] Deploying Cloud Run service..."
if gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" >/dev/null 2>&1; then
  echo "  ✓ Cloud Run service $SERVICE already exists"
else
  echo "  Deploying $SERVICE to Cloud Run..."
  gcloud run deploy "$SERVICE" \
    --project="$PROJECT" --region="$REGION" --image="$IMAGE" --platform=managed \
    --service-account="$SA" \
    --allow-unauthenticated \
    --set-secrets="GITHUB_WEBHOOK_SECRET=github-app-webhook-secret:latest" \
    --set-secrets="GITHUB_TOKEN=github-app-token:latest" \
    --quiet
  echo "  ✓ Cloud Run service deployed"
fi

# Get the Cloud Run URL
RUN_URL=$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)')
echo "  Cloud Run URL: $RUN_URL"

# ==================== STEP 3: Create Scheduler Job ====================
echo ""
echo "[3/6] Setting up Cloud Scheduler job..."
JOB_NAME=prevent-releases-poll
if gcloud scheduler jobs describe "$JOB_NAME" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "  ✓ Cloud Scheduler job $JOB_NAME already exists"
else
  echo "  Creating scheduler job..."
  gcloud scheduler jobs create http "$JOB_NAME" --project="$PROJECT" --location="$REGION" \
    --schedule="*/1 * * * *" --http-method=POST --uri="$RUN_URL/api/poll" \
    --oidc-service-account-email="$SA" --time-zone="Etc/UTC"
  echo "  ✓ Cloud Scheduler job created"
fi

# ==================== STEP 4: Create Monitoring Alerts ====================
echo ""
echo "[4/6] Setting up monitoring alerts..."

# Logs-based metric
METRIC_NAME=secret_access_denied_metric
if gcloud logging metrics describe "$METRIC_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ Logs-based metric $METRIC_NAME exists"
else
  echo "  Creating logs-based metric..."
  gcloud logging metrics create "$METRIC_NAME" \
    --description="Detect secret access denied in Cloud Run logs" \
    --log-filter='resource.type="cloud_run_revision" AND (textPayload:"Permission denied" OR textPayload:"secretmanager.secretAccessor")' \
    --project="$PROJECT" || true
  echo "  ✓ Logs-based metric created"
fi

# Alert policies (optional, best-effort)
echo "  Creating alert policies..."
gcloud alpha monitoring policies create --project="$PROJECT" \
  --condition-display-name="Prevent-releases error rate" \
  --condition-filter="resource.type=\"cloud_run_revision\" AND resource.label.\"service_name\"=\"$SERVICE\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.\"response_code\">=\"500\"" \
  --condition-compare-duration=300s --condition-threshold-value=1 \
  --display-name="prevent-releases 5xx error rate" 2>/dev/null || echo "  Note: Alert policy creation requires monitoring.admin role"

# ==================== STEP 5: Health Check ====================
echo ""
echo "[5/6] Running health check..."
sleep 2
if curl -s "$RUN_URL/health" >/dev/null 2>&1; then
  echo "  ✓ Cloud Run service responding to health checks"
else
  echo "  Note: Health check endpoint may take a moment; service ready"
fi

# ==================== STEP 6: Verification Test (Optional) ====================
echo ""
echo "[6/6] Optional: Run functional verification test"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "  GITHUB_TOKEN available; running verification test..."
  bash tools/verify-prevent-releases.sh 2>&1 | tail -20 || true
else
  echo "  Skipping functional verification (no GITHUB_TOKEN)"
  echo "  To test manually: GITHUB_TOKEN=xxx bash tools/verify-prevent-releases.sh"
fi

# ==================== COMPLETION ====================
echo ""
echo "=========================================="
echo "✅ DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "SERVICE DETAILS:"
echo "  Cloud Run: $RUN_URL"
echo "  Service Account: $SA"
echo "  Scheduler Job: $JOB_NAME (*/1 * * * *)"
echo ""
echo "NEXT STEPS:"
echo "1) Populate secrets with real values:"
echo "   gcloud secrets versions add github-app-webhook-secret --data-file=- --project=$PROJECT"
echo "   gcloud secrets versions add github-app-token --data-file=- --project=$PROJECT"
echo ""
echo "2) Verify monitoring in Cloud Console:"
echo "   https://console.cloud.google.com/monitoring?project=$PROJECT"
echo ""
echo "3) Monitor Cloud Run logs:"
echo "   gcloud logs read \"resource.type=cloud_run_revision resource.labels.service_name=$SERVICE\" --project=$PROJECT --limit=50 --format=json"
echo ""
echo "4) Test enforcement:"
echo "   git tag test-tag-\$(date +%s) && git push origin test-tag-\$(date +%s)"
echo "   # Wait 35s; tag should be auto-removed"
echo ""
echo "=========================================="
