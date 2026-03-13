#!/usr/bin/env bash
# Verify that all Phase0 automation is running and working correctly.

set -euo pipefail

PROJECT_ID="${1:-}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 <PROJECT_ID>"
  exit 1
fi

echo "====== Phase0 Verification Report ======"
echo "Project: $PROJECT_ID"
echo ""

# Check KMS keyring
echo "[1/5] Checking KMS keyring..."
if gcloud kms keyrings list --location=us-central1 --project="$PROJECT_ID" --filter='name:nexus-keyring' | grep -q nexus-keyring; then
  echo "✅ KMS keyring found: nexus-keyring"
else
  echo "❌ KMS keyring not found"
fi

# Check Secret Manager secret
echo "[2/5] Checking Secret Manager secret..."
if gcloud secrets list --project="$PROJECT_ID" --filter='name:nexus-app-secret' 2>/dev/null | grep -q nexus-app-secret; then
  echo "✅ Secret found: nexus-app-secret"
else
  echo "❌ Secret not found"
fi

# Check Cloud Build trigger
echo "[3/5] Checking Cloud Build trigger..."
if gcloud builds triggers list --project="$PROJECT_ID" --filter='name:nexus-deploy-trigger' 2>/dev/null | grep -q nexus-deploy-trigger; then
  echo "✅ Cloud Build trigger found: nexus-deploy-trigger"
else
  echo "❌ Cloud Build trigger not found"
fi

# Check latest Cloud Build
echo "[4/5] Checking latest Cloud Build job..."
LATEST_BUILD=$(gcloud builds list --project="$PROJECT_ID" --limit=1 --format='value(id)' 2>/dev/null || echo "")
if [[ -n "$LATEST_BUILD" ]]; then
  BUILD_STATUS=$(gcloud builds log "$LATEST_BUILD" --project="$PROJECT_ID" --limit=5 2>&1 | tail -1 || echo "unknown")
  echo "✅ Latest build: $LATEST_BUILD"
  echo "  Status: $BUILD_STATUS"
else
  echo "⚠️  No builds found yet"
fi

# Check GitHub branch protection
echo "[5/5] Checking GitHub branch protection (if configured)..."
echo "⚠️  Manual verification: https://github.com/ORG/REPO/settings/branches"

echo ""
echo "====== Verification Complete ======"
