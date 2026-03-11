#!/usr/bin/env bash
set -euo pipefail

# MINIMAL BOOTSTRAP FOR DEPLOYER SA CREATION & KEY STORAGE
# Workaround when Project Owner permissions unavailable
# Creates deployer-sa and stores key in GSM without role-binding

PROJECT=${PROJECT:-nexusshield-prod}
DEPL_SA_NAME=deployer-sa
DEPL_SA=${DEPL_SA_NAME}@${PROJECT}.iam.gserviceaccount.com
SECRET_NAME=deployer-sa-key
TMP_KEY=/tmp/deployer-sa-key.json

echo "=========================================="
echo "MINIMAL DEPLOYER SA BOOTSTRAP"
echo "Project: $PROJECT"
echo "=========================================="
echo ""

# Step 1: Create deployer service account (idempotent)
echo "[1/3] Creating deployer service account..."
if gcloud iam service-accounts describe "$DEPL_SA" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ Service account $DEPL_SA already exists"
else
  gcloud iam service-accounts create "$DEPL_SA_NAME" \
    --project="$PROJECT" \
    --display-name="Deployer SA (Cloud Run deployment)" \
    --quiet
  echo "  ✓ Service account created: $DEPL_SA"
fi

# Step 2: Create and store key in GSM
echo ""
echo "[2/3] Creating SA key and storing in Secret Manager..."
if [ -f "$TMP_KEY" ]; then
  rm -f "$TMP_KEY"
fi

gcloud iam service-accounts keys create "$TMP_KEY" \
  --iam-account="$DEPL_SA" \
  --project="$PROJECT" \
  --quiet
echo "  ✓ Key created at $TMP_KEY"

# Step 3: Store in GSM (create or update)
echo "[3/3] Storing key in GSM..."
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

# Cleanup
rm -f "$TMP_KEY"

echo ""
echo "=========================================="
echo "✅ BOOTSTRAP COMPLETE (Minimal)"
echo "=========================================="
echo ""
echo "DEPLOYED SA: $DEPL_SA"
echo "SECRET NAME: $SECRET_NAME"
echo ""
echo "Note: Role binding to orchestrator SA requires Project Owner action:"
echo "  gcloud projects add-iam-policy-binding $PROJECT \\"
echo "    --member=serviceAccount:secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com \\"
echo "    --role=roles/run.admin"
echo ""
echo "Deployer SA requires these roles (Project Owner to grant):"
echo "  - roles/run.admin"
echo "  - roles/iam.serviceAccountUser"
echo ""
echo "=========================================="
