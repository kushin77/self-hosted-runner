#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PREVENT-RELEASES DEPLOYER SA BOOTSTRAP
# ============================================================================
# One-time setup script for GCP admin to create deployer service account,
# grant roles, and store credentials in Google Secret Manager for automated
# deployment orchestration.
#
# REQUIRES: GCP Project Owner or IAM Admin role
#
# USAGE:
#   bash infra/bootstrap-deployer-run.sh
#
# AFTER RUNNING:
#   - infra/deploy-prevent-releases-final.sh will auto-activate deployer SA
#   - All future deployments fully automated (no manual IAM grants needed)
#
# ============================================================================

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
DEPL_SA_NAME=deployer-run
DEPL_SA=${DEPL_SA_NAME}@${PROJECT}.iam.gserviceaccount.com
SECRET_NAME=deployer-sa-key
ORCH_SA=secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com
TMP_KEY=/tmp/deployer-sa-key.json

echo "=========================================="
echo "PREVENT-RELEASES DEPLOYER SA BOOTSTRAP"
echo "Project: $PROJECT | Region: $REGION"
echo "=========================================="
echo ""

# Verify user has permissions
echo "[1/6] Verifying admin permissions..."
if ! gcloud projects get-iam-policy "$PROJECT" --format=json >/dev/null 2>&1; then
  echo "ERROR: Cannot access $PROJECT. Ensure you have Project Owner or IAM Admin role."
  exit 1
fi
echo "  ✓ Admin permissions verified"

# Step 1: Create service account
echo ""
echo "[2/6] Creating service account $DEPL_SA_NAME..."
if gcloud iam service-accounts describe "$DEPL_SA" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ Service account already exists"
else
  gcloud iam service-accounts create "$DEPL_SA_NAME" \
    --project="$PROJECT" \
    --display-name="Deployer Run (Cloud Run deployment automation)" \
    --quiet
  echo "  ✓ Service account created"
fi

# Step 2: Grant roles/run.admin
echo ""
echo "[3/6] Granting roles/run.admin to $DEPL_SA..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$DEPL_SA" \
  --role="roles/run.admin" \
  --condition=None \
  --quiet
echo "  ✓ roles/run.admin granted"

# Step 3: Grant roles/iam.serviceAccountUser
echo ""
echo "[4/6] Granting roles/iam.serviceAccountUser to $DEPL_SA..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$DEPL_SA" \
  --role="roles/iam.serviceAccountUser" \
  --condition=None \
  --quiet
echo "  ✓ roles/iam.serviceAccountUser granted"

# Step 4: Create and store key
echo ""
echo "[5/6] Creating SA key and storing in GSM..."
gcloud iam service-accounts keys create "$TMP_KEY" \
  --iam-account="$DEPL_SA" \
  --quiet
echo "  ✓ Key created at $TMP_KEY"

# Step 5: Store in GSM (create or update)
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud secrets versions add "$SECRET_NAME" \
    --data-file="$TMP_KEY" \
    --project="$PROJECT" \
    --quiet
  echo "  ✓ Secret $SECRET_NAME updated with new version"
else
  gcloud secrets create "$SECRET_NAME" \
    --data-file="$TMP_KEY" \
    --project="$PROJECT" \
    --replication-policy="automatic" \
    --quiet
  echo "  ✓ Secret $SECRET_NAME created"
fi

# Step 6: Grant secret access to orchestrator SA
echo ""
echo "[6/6] Granting secret access to orchestrator SA..."
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --project="$PROJECT" \
  --member="serviceAccount:$ORCH_SA" \
  --role="roles/secretmanager.secretAccessor" \
  --condition=None \
  --quiet
echo "  ✓ Orchestrator SA can access secret"

# Cleanup
rm -f "$TMP_KEY"

echo ""
echo "=========================================="
echo "✅ BOOTSTRAP COMPLETE"
echo "=========================================="
echo ""
echo "NEXT STEPS:"
echo "1) Deployment is now fully automated"
echo "2) Run: bash infra/deploy-prevent-releases-final.sh"
echo "3) Orchestrator will auto-activate deployer SA and deploy Cloud Run"
echo ""
echo "SERVICE DETAILS:"
echo "  - Deployer SA: $DEPL_SA"
echo "  - Secret Name: $SECRET_NAME"
echo "  - Project: $PROJECT"
echo ""
echo "=========================================="
