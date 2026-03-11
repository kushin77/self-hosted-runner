#!/usr/bin/env bash
set -euo pipefail

# Grant required IAM roles, create a minimal deployer role and SA, and store key in GSM.
# MUST be run as a GCP Project Owner or IAM Admin for project nexusshield-prod.

PROJECT=${PROJECT:-nexusshield-prod}
DEPL_ROLE_ID=deployerMinimal
DEPL_ROLE_TITLE="Deployer Minimal"
DEPL_SA_NAME=deployer-sa
DEPL_SA=${DEPL_SA_NAME}@${PROJECT}.iam.gserviceaccount.com
SECRET_NAME=deployer-sa-key
TMP_KEY=/tmp/deployer-sa-key.json

echo "Project: $PROJECT"
echo "This script creates a minimal custom role, service account, and stores a key in GSM. Run as Project Owner."

echo "[1/5] Granting orchestrator basic admin roles to secrets-orch-sa..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member=serviceAccount:secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com \
  --role=roles/run.admin --quiet || true
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member=serviceAccount:secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountAdmin --quiet || true
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member=serviceAccount:secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com \
  --role=roles/iam.roleAdmin --quiet || true

echo "[2/5] Creating custom role '$DEPL_ROLE_ID' (idempotent)..."
if gcloud iam roles describe "$DEPL_ROLE_ID" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ Custom role $DEPL_ROLE_ID already exists"
else
  # Define a minimal permissions list for deployment
  PERMS=(
    "run.services.create"
    "run.services.get"
    "run.services.update"
    "iam.serviceAccounts.create"
    "iam.serviceAccounts.get"
    "iam.serviceAccounts.actAs"
    "secretmanager.secrets.create"
    "secretmanager.versions.add"
    "cloudscheduler.jobs.create"
    "logging.logEntries.create"
    "monitoring.policies.create"
  )
  gcloud iam roles create "$DEPL_ROLE_ID" --project="$PROJECT" \
    --title="$DEPL_ROLE_TITLE" \
    --permissions="$(IFS=,; echo "${PERMS[*]}")" --stage=GA --quiet
  echo "  ✓ Custom role created: $DEPL_ROLE_ID"
fi

echo "[3/5] Creating deployer service account (idempotent)..."
if gcloud iam service-accounts describe "$DEPL_SA" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ Service account $DEPL_SA already exists"
else
  gcloud iam service-accounts create "$DEPL_SA_NAME" \
    --project="$PROJECT" --display-name="Deployer SA" --quiet
  echo "  ✓ Service account created: $DEPL_SA"
fi

echo "[4/5] Binding custom role to deployer service account..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member=serviceAccount:${DEPL_SA} \
  --role=projects/${PROJECT}/roles/${DEPL_ROLE_ID} --quiet || true

echo "[5/5] Creating service account key and storing in Secret Manager..."
if [ -f "$TMP_KEY" ]; then
  rm -f "$TMP_KEY"
fi
gcloud iam service-accounts keys create "$TMP_KEY" --iam-account="$DEPL_SA" --project="$PROJECT" --quiet

if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud secrets versions add "$SECRET_NAME" --data-file="$TMP_KEY" --project="$PROJECT" --quiet
  echo "  ✓ Secret $SECRET_NAME updated with new key version"
else
  gcloud secrets create "$SECRET_NAME" --data-file="$TMP_KEY" --project="$PROJECT" --replication-policy="automatic" --quiet
  echo "  ✓ Secret $SECRET_NAME created"
fi

echo "Bootstrap complete. The orchestrator will be able to activate the deployer SA from GSM."
echo "You can now run: bash infra/deploy-prevent-releases.sh"
