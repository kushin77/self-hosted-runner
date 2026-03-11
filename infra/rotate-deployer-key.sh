#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:-nexusshield-prod}
DEPL_SA=deployer-run@${PROJECT}.iam.gserviceaccount.com
SECRET_NAME=deployer-sa-key
TMP_NEW=/tmp/deployer-sa-key-rotate-$(date +%Y%m%d-%H%M%S).json

echo "[1/4] Creating new key for $DEPL_SA at $TMP_NEW"
gcloud iam service-accounts keys create "$TMP_NEW" --iam-account="$DEPL_SA" --project="$PROJECT" --quiet

echo "[2/4] Adding new key to Secret Manager as new version: $SECRET_NAME"
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud secrets versions add "$SECRET_NAME" --data-file="$TMP_NEW" --project="$PROJECT" --quiet
  echo "  ✓ Secret $SECRET_NAME updated with new version"
else
  gcloud secrets create "$SECRET_NAME" --data-file="$TMP_NEW" --project="$PROJECT" --replication-policy="automatic" --quiet
  echo "  ✓ Secret $SECRET_NAME created"
fi

echo "[3/4] Verifying new secret version accessible"
if gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  echo "  ✓ New secret version accessible"
else
  echo "  ⚠ Failed to verify new secret version"
  exit 1
fi

echo "[4/4] Rotation complete. New key stored as latest secret version."

echo "IMPORTANT: Old keys are retained to allow immediate rollback. To remove old keys, run manually after verification:"
echo "  gcloud iam service-accounts keys list --iam-account=$DEPL_SA --project=$PROJECT"
echo "  gcloud iam service-accounts keys delete KEY_ID --iam-account=$DEPL_SA --project=$PROJECT"

echo "To automate deletion, add logic here and ensure you have at least one valid key before removing others."

# Clean up local file
rm -f "$TMP_NEW"

echo "Rotation finished. New key is the active version in Secret Manager: $SECRET_NAME"
