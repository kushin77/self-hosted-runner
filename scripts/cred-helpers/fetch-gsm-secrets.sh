#!/bin/bash
#
# GCP Secret Manager credential fetcher
# Authenticates via OIDC, retrieves secrets from Google Secret Manager
# Usage: ./fetch-gsm-secrets.sh <project_id> <secret_name> [version]
#

set -euo pipefail

PROJECT_ID="${1:?Project ID required}"
SECRET_NAME="${2:?Secret name required}"
VERSION="${3:-latest}"

# Retrieve OIDC token from GitHub Actions
OIDC_TOKEN="${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?OIDC token not available}"
OIDC_ENDPOINT="${ACTIONS_ID_TOKEN_REQUEST_URL:?OIDC endpoint not configured}"

# Request OIDC token with audience set to Google
TOKEN_RESPONSE=$(curl -s -H "Authorization: bearer $OIDC_TOKEN" \
  "${OIDC_ENDPOINT}&audience=https://iamcredentials.goog/google.iam.v1.WorkloadIdentityTokenProvider")

GOOGLE_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token' 2>/dev/null || echo "")

if [[ -z "$GOOGLE_TOKEN" || "$GOOGLE_TOKEN" == "null" ]]; then
  echo "❌ Failed to obtain Google OIDC token" >&2
  exit 1
fi

# Exchange for Google access token
ACCESS_TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"grant_type\":\"urn:ietf:params:oauth:grant-type:token-exchange\",\"subject_token\":\"$GOOGLE_TOKEN\",\"subject_token_type\":\"urn:ietf:params:oauth:token-type:jwt\",\"scope\":\"https://www.googleapis.com/auth/cloud-platform\"}" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/sa@model-context-protocol.iam.gserviceaccount.com:generateAccessToken")

ACCESS_TOKEN=$(echo "$ACCESS_TOKEN_RESPONSE" | jq -r '.accessToken' 2>/dev/null || echo "")

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "❌ Failed to obtain Google access token" >&2
  exit 1
fi

# Fetch secret from Secret Manager
SECRET_VALUE=$(curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/$PROJECT_ID/secrets/$SECRET_NAME/versions/$VERSION:access")

if [[ $? -ne 0 ]]; then
  echo "❌ Failed to retrieve secret from GSM" >&2
  exit 1
fi

# Extract payload (base64 decoded)
echo "$SECRET_VALUE" | jq -r '.payload.data' | base64 -d

exit 0
