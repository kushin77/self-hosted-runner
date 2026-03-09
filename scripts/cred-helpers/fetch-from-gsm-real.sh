#!/usr/bin/env bash
set -euo pipefail

# Fetch secret from Google Secret Manager (GSM)
# Usage: fetch-from-gsm-real.sh <CREDENTIAL_NAME>

CREDENTIAL_NAME="${1:-}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"

log_info(){ echo "[INFO] $1" >&2; }
log_warn(){ echo "[WARN] $1" >&2; }
log_pass(){ echo "[PASS] $1" >&2; }
log_fail(){ echo "[FAIL] $1" >&2; }

if [ -z "$CREDENTIAL_NAME" ]; then
  log_fail "Usage: $0 CREDENTIAL_NAME"
  exit 2
fi

if [ -z "$GCP_PROJECT_ID" ]; then
  log_warn "GCP_PROJECT_ID not configured, skipping GSM layer"
  exit 1
fi

log_info "Attempting GSM retrieval for $CREDENTIAL_NAME..."

# Get OIDC token (optional)
OIDC_TOKEN=""
if [[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
  RESP=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}?audience=https://iamcredentials.googleapis.com" \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" 2>/dev/null || true)
  OIDC_TOKEN=$(echo "$RESP" | jq -r '.token // empty' 2>/dev/null || echo "")
fi

if [ -z "$OIDC_TOKEN" ]; then
  log_warn "OIDC token not available, trying ADC..."
fi

CRED_VALUE=""
for attempt in 1 2 3; do
  CRED_VALUE=$(gcloud secrets versions access latest --secret="$CREDENTIAL_NAME" --project="$GCP_PROJECT_ID" 2>/dev/null || echo "")
  if [ -n "$CRED_VALUE" ]; then
    log_pass "GSM retrieval successful (attempt $attempt)"
    echo "$CRED_VALUE"
    exit 0
  fi
  if [ $attempt -lt 3 ]; then sleep $((attempt * 2)); fi
done

log_fail "GSM retrieval failed after 3 attempts"
exit 1
