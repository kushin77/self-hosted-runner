#!/usr/bin/env bash
# Vault AppRole Rotation - Operator Handoff Helper
# Usage: ./scripts/secrets/enable-vault-rotation.sh <VAULT_ADDR> <VAULT_TOKEN>
# This script safely stores Vault credentials and executes the first rotation.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <VAULT_ADDR> <VAULT_TOKEN>"
  echo ""
  echo "Example:"
  echo "  $0 'https://vault.example.com:8200' 's.xxxxxxxxxxxxxxxx'"
  echo ""
  exit 1
fi

VAULT_ADDR="$1"
VAULT_TOKEN="$2"
PROJECT="nexusshield-prod"

echo "=== Vault AppRole Rotation Setup ==="
echo "Storing credentials in Google Secret Manager..."

# Validate Vault address
if ! echo "$VAULT_ADDR" | grep -qE '^https?://'; then
  echo "ERROR: VAULT_ADDR must start with http:// or https://"
  exit 1
fi

# Store credentials in GSM
echo "Adding VAULT_ADDR to GSM..."
echo -n "$VAULT_ADDR" | gcloud secrets versions add VAULT_ADDR --data-file=- --project="$PROJECT"

echo "Adding VAULT_TOKEN to GSM..."
echo -n "$VAULT_TOKEN" | gcloud secrets versions add VAULT_TOKEN --data-file=- --project="$PROJECT"

echo "✓ Credentials stored in GSM"
echo ""
echo "=== Testing Vault Connectivity ==="

# Test connectivity to Vault
HEALTH_CHECK=$(curl -sfS --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo '{}')
if echo "$HEALTH_CHECK" | jq -e '.initialized' >/dev/null 2>&1; then
  echo "✓ Vault is reachable and initialized"
else
  echo "⚠ WARNING: Could not verify Vault connectivity. Proceeding anyway..."
fi

echo ""
echo "=== Running First Rotation ==="
echo "Executing Cloud Build to rotate AppRole secret_id..."

BUILD_ID=$(gcloud builds submit . --config=cloudbuild/run-vault-rotation.yaml \
  --substitutions=_GSM_PROJECT="$PROJECT" \
  --timeout=600s \
  --format='value(id)' 2>/dev/null | tail -n 1)

if [[ -n "$BUILD_ID" ]]; then
  echo "Build submitted: $BUILD_ID"
  echo ""
  echo "View build logs:"
  echo "  gcloud builds log $BUILD_ID --stream --project=$PROJECT"
  echo ""
  echo "Waiting for build to complete (timeout: 10 minutes)..."
  
  if gcloud builds wait "$BUILD_ID" --project="$PROJECT" 2>/dev/null; then
    STATUS=$(gcloud builds describe "$BUILD_ID" --project="$PROJECT" --format='value(status)')
    if [[ "$STATUS" == "SUCCESS" ]]; then
      echo "✓ Rotation completed successfully!"
      echo ""
      echo "New secret version stored in GSM:"
      gcloud secrets versions list vault-example-role-secret_id --project="$PROJECT" --limit=1
    else
      echo "✗ Build completed with status: $STATUS"
      echo "Check logs: gcloud builds log $BUILD_ID --project=$PROJECT"
      exit 1
    fi
  else
    echo "⚠ Build did not complete within timeout. Check status:"
    echo "  gcloud builds describe $BUILD_ID --project=$PROJECT"
  fi
else
  echo "ERROR: Failed to submit build"
  exit 1
fi

echo ""
echo "=== Rotation Enabled ==="
echo "Daily rotation scheduled for 03:00 UTC via Cloud Scheduler job: vault-rotation-schedule"
echo ""
echo "To verify setup:"
echo "  gcloud scheduler jobs describe vault-rotation-schedule --location=us-central1 --project=$PROJECT"
echo ""
echo "To view rotation history:"
echo "  gcloud logging read 'resource.type=cloud_build AND logName=~\"vault-rotation\"' --project=$PROJECT --limit=10 --format=json"
