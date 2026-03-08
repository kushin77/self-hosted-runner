#!/usr/bin/env bash
set -euo pipefail

# Fetch a secret from Google Secret Manager (GSM)
# Usage: fetch-gcp-secret.sh <secret-name> [project-id]
# Returns: Secret value via stdout (suitable for piping to env vars)
# Exit code: 0 on success, 1 on failure

SECRET_NAME="${1:?Secret name required (e.g., pagerduty-integration-key)}"
PROJECT_ID="${2:${GCP_PROJECT_ID:-}}"

if [ -z "$PROJECT_ID" ]; then
  echo "❌ ERROR: GCP_PROJECT_ID not set and no project-id argument provided" >&2
  exit 1
fi

# Validate gcloud is available
if ! command -v gcloud &>/dev/null; then
  echo "❌ ERROR: gcloud CLI not found in PATH" >&2
  exit 1
fi

# Fetch secret from GSM
# Uses Application Default Credentials (ADC) or OIDC federation
echo "🔍 Fetching secret from GSM: projects/$PROJECT_ID/secrets/$SECRET_NAME" >&2

SECRET_VALUE=$(gcloud secrets versions access latest \
  --secret="$SECRET_NAME" \
  --project="$PROJECT_ID" 2>/dev/null) || {
  echo "❌ ERROR: Failed to fetch secret '$SECRET_NAME' from GSM" >&2
  echo "   Project: $PROJECT_ID" >&2
  echo "   Ensure:" >&2
  echo "   1. Secret exists in GSM" >&2
  echo "   2. GitHub OIDC service account has roles/secretmanager.secretAccessor" >&2
  echo "   3. OIDC is configured in GCP workload identity federation" >&2
  exit 1
}

if [ -z "$SECRET_VALUE" ]; then
  echo "❌ ERROR: Secret '$SECRET_NAME' is empty in GSM" >&2
  exit 1
fi

# Return the secret value (masked in logs by GitHub Actions when exported)
echo "$SECRET_VALUE"
echo "✅ Secret fetched from GSM" >&2
