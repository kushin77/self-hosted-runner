#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PREVENT-RELEASES MASTER DEPLOYMENT ORCHESTRATOR
# ============================================================================
# Automated first-deployment handler
#
# Workflow:
# 1. Check if deployer-sa-key secret exists (first-time bootstrap done)
# 2. If yes: run full deployment with auto-activated deployer SA
# 3. If no: provide bootstrap instructions
#
# Usage: bash infra/deploy-prevent-releases.sh
# ============================================================================

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
SECRET_NAME=deployer-sa-key

echo "=========================================="
echo "PREVENT-RELEASES DEPLOYMENT ORCHESTRATOR"
echo "Project: $PROJECT | Region: $REGION"
echo "=========================================="
echo ""

# Check if bootstrap has been completed
echo "[PRE] Checking deployment bootstrap status..."
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ Bootstrap complete: deployer-sa-key secret found"
  echo ""
  echo "Proceeding with full deployment orchestrator..."
  echo ""
  bash infra/deploy-prevent-releases-final.sh
else
  echo "  ⚠ Bootstrap required: deployer-sa-key secret not found"
  echo ""
  echo "First-time deployment requires one-time GCP admin bootstrap."
  echo ""
  echo "OPTIONS:"
  echo ""
  echo "Option A (Admin bootstraps deployer SA + GSM secret):"
  echo "  bash infra/bootstrap-deployer-run.sh"
  echo ""
  echo "Option B (Admin grants permissions directly):"
  echo "  gcloud projects add-iam-policy-binding nexusshield-prod \\"
  echo "    --member=serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com \\"
  echo "    --role=roles/run.admin --condition=None --quiet"
  echo ""
  echo "After either option, re-run:"
  echo "  bash infra/deploy-prevent-releases.sh"
  echo ""
  exit 1
fi
