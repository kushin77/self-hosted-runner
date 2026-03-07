#!/bin/bash
# Enhanced GCP Service Account Key Validator
# Purpose: Validate and diagnose GCP service-account JSON structure with detailed feedback
# Features: Safe secret handling, field extraction, recovery hints, idempotent

set -e

GCP_KEY_SECRET="${GCP_SERVICE_ACCOUNT_KEY:-}"
OUTPUT_FILE="${1:-.github/_gcp_validation_output.txt}"

echo "=== GCP Service Account Key Validation ===" | tee -a "$OUTPUT_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$OUTPUT_FILE"
echo ""

# Step 1: Check if secret exists
if [ -z "$GCP_KEY_SECRET" ]; then
  echo "❌ ERROR: GCP_SERVICE_ACCOUNT_KEY is empty or not set" | tee -a "$OUTPUT_FILE"
  echo "RECOVERY: Set the secret in GitHub repo settings → Secrets & variables → Repository secrets" | tee -a "$OUTPUT_FILE"
  exit 1
fi

# Step 2: Check length (basic sanity check)
KEY_LEN=${#GCP_KEY_SECRET}
if [ "$KEY_LEN" -lt 100 ]; then
  echo "⚠️ WARNING: GCP key is unusually short ($KEY_LEN bytes); may be truncated or invalid" | tee -a "$OUTPUT_FILE"
fi

# Step 3: Validate JSON structure
if ! echo "$GCP_KEY_SECRET" | jq empty 2>/dev/null; then
  echo "❌ ERROR: GCP key is not valid JSON" | tee -a "$OUTPUT_FILE"
  echo "RECOVERY: Ensure the secret is a valid service-account JSON file" | tee -a "$OUTPUT_FILE"
  echo "  Run locally: jq . < /path/to/service-account.json" | tee -a "$OUTPUT_FILE"
  exit 1
fi

echo "✅ GCP key is valid JSON (length: $KEY_LEN bytes)" | tee -a "$OUTPUT_FILE"
echo ""

# Step 4: Extract and validate required fields
TYPE=$(echo "$GCP_KEY_SECRET" | jq -r '.type // "MISSING"')
PROJECT_ID=$(echo "$GCP_KEY_SECRET" | jq -r '.project_id // "MISSING"')
CLIENT_EMAIL=$(echo "$GCP_KEY_SECRET" | jq -r '.client_email // "MISSING"')
PRIVATE_KEY_ID=$(echo "$GCP_KEY_SECRET" | jq -r '.private_key_id // "MISSING"')

echo "Extracted fields:" | tee -a "$OUTPUT_FILE"
echo "  type: $TYPE" | tee -a "$OUTPUT_FILE"
echo "  project_id: $PROJECT_ID" | tee -a "$OUTPUT_FILE"
echo "  client_email: ${CLIENT_EMAIL:0:20}... (truncated)" | tee -a "$OUTPUT_FILE"
echo "  private_key_id: ${PRIVATE_KEY_ID:0:10}... (truncated)" | tee -a "$OUTPUT_FILE"
echo ""

# Step 5: Validate required fields
MISSING_FIELDS=()
[ "$TYPE" != "service_account" ] && MISSING_FIELDS+=("type != 'service_account' (got: $TYPE)")
[ "$PROJECT_ID" = "MISSING" ] && MISSING_FIELDS+=("project_id")
[ "$CLIENT_EMAIL" = "MISSING" ] && MISSING_FIELDS+=("client_email")
[ "$PRIVATE_KEY_ID" = "MISSING" ] && MISSING_FIELDS+=("private_key_id")

if [ ${#MISSING_FIELDS[@]} -gt 0 ]; then
  echo "❌ ERROR: GCP key missing required fields:" | tee -a "$OUTPUT_FILE"
  for field in "${MISSING_FIELDS[@]}"; do
    echo "  - $field" | tee -a "$OUTPUT_FILE"
  done
  echo "" | tee -a "$OUTPUT_FILE"
  echo "RECOVERY STEPS:" | tee -a "$OUTPUT_FILE"
  echo "  1. Download a valid service-account JSON from GCP Console" | tee -a "$OUTPUT_FILE"
  echo "  2. Verify locally: jq . < /path/to/service-account.json" | tee -a "$OUTPUT_FILE"
  echo "  3. Update the secret: gh secret set GCP_SERVICE_ACCOUNT_KEY --body '$(cat /path/to/service-account.json)'" | tee -a "$OUTPUT_FILE"
  echo "  4. Comment 'ingested: true' on Issue #1239 to re-trigger workflows" | tee -a "$OUTPUT_FILE"
  exit 1
fi

echo "✅ GCP key has all required fields" | tee -a "$OUTPUT_FILE"
echo "✅ Validation SUCCESSFUL" | tee -a "$OUTPUT_FILE"
echo "status=valid" >> "$GITHUB_OUTPUT"
exit 0
