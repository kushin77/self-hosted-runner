#!/bin/bash
################################################################################
# OPERATOR TOKEN INJECTION & AUTO-EXECUTION
# Purpose: Inject Cloudflare token into GSM and trigger finalization immediately
# Usage: bash scripts/ops/operator-inject-token.sh "<CLOUDFLARE_API_TOKEN>"
################################################################################

if [ $# -eq 0 ]; then
  echo "❌ ERROR: Cloudflare API token required"
  echo ""
  echo "Usage: $0 <CF_API_TOKEN>"
  echo ""
  echo "Steps to obtain token:"
  echo "  1. Go to Cloudflare Dashboard → My Profile → API Tokens"
  echo "  2. Create token with permissions: Zone.DNS:Edit"
  echo "  3. Copy token value"
  echo "  4. Run: $0 '<token_value>'"
  echo ""
  exit 1
fi

CF_API_TOKEN="$1"
PROJECT_ID="nexusshield-prod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] TOKEN INJECTION: Starting"
echo ""

# Validate token format (rough check)
if [ ${#CF_API_TOKEN} -lt 30 ]; then
  echo "❌ ERROR: Token appears invalid (too short). Expected Cloudflare API token."
  exit 1
fi

# Create or update secret in GSM
echo "📝 Updating cloudflare-api-token in GSM (nexusshield-prod)..."

# Try to create secret (if it exists, this will fail gracefully)
gcloud secrets create cloudflare-api-token \
  --project="$PROJECT_ID" \
  --replication-policy="automatic" \
  --data-file=/dev/stdin <<< "$CF_API_TOKEN" 2>&1 | grep -v "already exists" || true

# Now add a new version (works whether secret is new or existing)
echo -n "$CF_API_TOKEN" | gcloud secrets versions add cloudflare-api-token \
  --project="$PROJECT_ID" \
  --data-file=/dev/stdin

echo "✓ Token added to GSM"
echo ""

# Verify token is accessible
VERIFY_TOKEN=$(gcloud secrets versions access latest --secret=cloudflare-api-token --project="$PROJECT_ID" 2>/dev/null || echo "")
if [ -n "$VERIFY_TOKEN" ] && [ "$VERIFY_TOKEN" = "$CF_API_TOKEN" ]; then
  echo "✓ Token verified in GSM"
else
  echo "❌ ERROR: Token verification failed"
  exit 1
fi

echo ""
echo "✅ TOKEN READY — Triggering Phase 2+3 finalization..."
echo ""

# Execute finalization with token available
export CF_API_TOKEN
cd "$REPO_ROOT"
bash scripts/ops/finalize-deployment.sh

exit $?
