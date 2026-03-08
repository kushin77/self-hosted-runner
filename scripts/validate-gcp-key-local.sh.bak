#!/usr/bin/env bash
set -euo pipefail

# Local validation script for operators to test GCP service account key before ingestion
# Usage: bash validate-gcp-key-local.sh /path/to/service-account.json
# Purpose: Validate key structure, required fields, and permissions locally

KEY_FILE="${1:?Usage: bash validate-gcp-key-local.sh /path/to/service-account.json}"

if [ ! -f "$KEY_FILE" ]; then
  echo "❌ ERROR: File not found: $KEY_FILE" >&2
  exit 1
fi

echo "=== GCP Service Account Key Local Validation ==="
echo "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "File: $KEY_FILE"
echo ""

# Check if jq is available
if ! command -v jq &>/dev/null; then
  echo "❌ ERROR: jq is required. Install with: brew install jq (macOS) or apt-get install jq (Linux)"
  exit 1
fi

# Validate JSON structure
if ! jq empty "$KEY_FILE" 2>/dev/null; then
  echo "❌ ERROR: Invalid JSON structure"
  jq . "$KEY_FILE" 2>&1 | head -10
  exit 1
fi

echo "✅ Valid JSON structure"
echo ""

# Check required fields
REQUIRED_FIELDS=("type" "project_id" "private_key_id" "private_key" "client_email" "client_id" "auth_uri" "token_uri")
MISSING_FIELDS=()

for field in "${REQUIRED_FIELDS[@]}"; do
  VALUE=$(jq -r ".$field // empty" "$KEY_FILE")
  if [ -z "$VALUE" ]; then
    MISSING_FIELDS+=("$field")
    echo "❌ Missing field: $field"
  else
    # Mask sensitive fields in output
    if [[ "$field" =~ (private_key|client_secret) ]]; then
      echo "✅ $field: [MASKED]"
    else
      echo "✅ $field: $VALUE"
    fi
  fi
done

echo ""

if [ ${#MISSING_FIELDS[@]} -gt 0 ]; then
  echo "❌ VALIDATION FAILED: Missing ${#MISSING_FIELDS[@]} required field(s): ${MISSING_FIELDS[*]}"
  echo ""
  echo "Recovery: Ensure your service account JSON includes all required fields."
  echo "          Download a new key from Google Cloud Console:"
  echo "          1. Go to https://console.cloud.google.com/iam-admin/serviceaccounts"
  echo "          2. Select service account"
  echo "          3. Keys tab → Create new key → JSON"
  exit 1
fi

echo "✅ All required fields present"
echo ""

# Validate private key format
PRIV_KEY=$(jq -r ".private_key" "$KEY_FILE")
if [[ "$PRIV_KEY" == *"-----BEGIN PRIVATE KEY-----"* ]]; then
  echo "✅ Private key format valid (PKCS#8)"
else
  echo "⚠️  WARNING: Private key may not be in standard PKCS#8 format"
fi

echo ""
echo "=== VALIDATION SUMMARY ==="
echo "Status: ✅ READY FOR INGESTION"
echo ""
echo "Next steps:"
echo "1. Set the secret in GitHub:"
echo "   gh secret set GCP_SERVICE_ACCOUNT_KEY < $KEY_FILE"
echo ""
echo "2. Post ingestion comment on Issue #1239:"
echo "   gh issue comment 1239 --repo kushin77/self-hosted-runner --body 'ingested: true'"
echo ""
echo "3. Monitor automation:"
echo "   Watch Issue #1239 for workflow updates (monitor polls every 5 minutes)"
echo ""
echo "=== END VALIDATION ==="
