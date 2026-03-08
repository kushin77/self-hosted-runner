#!/bin/bash
# Unified credential fetcher: attempts GSM (GCP Secret Manager) first or Vault first
# Controlled by env `CREDENTIAL_PREFERENCE`: values 'GSM' or 'VAULT' (default 'GSM')
# When running in GitHub Actions, outputs are written to $GITHUB_OUTPUT.

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_SERVICE_ACCOUNT_KEY_JSON="${GCP_SERVICE_ACCOUNT_KEY_JSON:-}"
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
VAULT_ROLE_ID="${VAULT_ROLE_ID:-}"
VAULT_SECRET_ID="${VAULT_SECRET_ID:-}"
AWS_SECRET_PATH="${AWS_SECRET_PATH:-aws/creds/prod}"
PREFERENCE="${CREDENTIAL_PREFERENCE:-GSM}"

GITHUB_OUT_PATH="${GITHUB_OUTPUT:-}"

log() { echo "[fetch-creds-unified] $*"; }
mask() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::$1"; fi }

write_output() {
  local k=$1; shift
  local v=$1; shift || true
  if [ -n "$GITHUB_OUT_PATH" ]; then
    echo "$k=$v" >> "$GITHUB_OUT_PATH"
  else
    # Print as fallback for local testing
    echo "$k=$v"
  fi
}

fetch_from_gsm() {
  if [ -z "$GCP_PROJECT_ID" ]; then
    log "GCP_PROJECT_ID not set; cannot fetch from GSM"
    return 1
  fi

  # If OIDC auth not available but a service account key is provided, use it
  if ! gcloud auth print-access-token >/dev/null 2>&1; then
    if [ -n "$GCP_SERVICE_ACCOUNT_KEY_JSON" ]; then
      log "OIDC not available — using provided service account key JSON"
      echo "$GCP_SERVICE_ACCOUNT_KEY_JSON" > /tmp/gcp_sa.json
      mask "$GCP_SERVICE_ACCOUNT_KEY_JSON"
      gcloud auth activate-service-account --key-file=/tmp/gcp_sa.json
    else
      log "OIDC auth not available and no service account key provided"
      return 1
    fi
  fi

  log "Fetching AWS secrets from Google Secret Manager..."
  AWS_ACCESS_KEY=$(gcloud secrets versions access latest --secret="terraform-aws-prod" --project="$GCP_PROJECT_ID" 2>/dev/null || true)
  AWS_SECRET=$(gcloud secrets versions access latest --secret="terraform-aws-secret" --project="$GCP_PROJECT_ID" 2>/dev/null || true)
  AWS_REGION=$(gcloud secrets versions access latest --secret="terraform-aws-region" --project="$GCP_PROJECT_ID" 2>/dev/null || echo "us-east-1")

  if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET" ]; then
    log "GSM did not return required AWS secrets"
    return 1
  fi

  mask "$AWS_ACCESS_KEY"
  mask "$AWS_SECRET"
  write_output aws_access_key_id "$AWS_ACCESS_KEY"
  write_output aws_secret_access_key "$AWS_SECRET"
  write_output aws_region "$AWS_REGION"
  log "Fetched credentials from GSM"
  return 0
}

fetch_from_vault() {
  if [ -z "$VAULT_ADDR" ]; then
    log "VAULT_ADDR not set; cannot fetch from Vault"
    return 1
  fi

  log "Fetching AWS credentials from Vault (AppRole)..."
  # Use the existing script if present
  if [ -x ./scripts/ops/fetch-creds-from-vault.sh ]; then
    # Ensure the inner script writes to GITHUB_OUTPUT when in Actions
    bash ./scripts/ops/fetch-creds-from-vault.sh
    # If running in Actions, the inner script already wrote outputs
    if [ -n "$GITHUB_OUT_PATH" ]; then
      # Try to read back outputs from env (inner script wrote to GITHUB_OUTPUT)
      # No-op here; assume inner script wrote aws_access_key_id/aws_secret_access_key
      log "Vault script executed (outputs expected in GITHUB_OUTPUT)"
      return 0
    fi
  fi

  # Fallback: attempt direct Vault API calls
  if [ -n "$VAULT_ROLE_ID" ] && [ -n "$VAULT_SECRET_ID" ]; then
    NS_HDR=""
    if [ -n "$VAULT_NAMESPACE" ]; then
      NS_HDR="-H X-Vault-Namespace:$VAULT_NAMESPACE"
    fi
    AUTH_RESP=$(curl -s $NS_HDR -X POST "$VAULT_ADDR/v1/auth/approle/login" -d "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}")
    VAULT_TOKEN=$(echo "$AUTH_RESP" | grep -o '"client_token":"[^"]*' | cut -d'"' -f4 || true)
    if [ -z "$VAULT_TOKEN" ]; then
      log "Vault AppRole auth failed"
      return 1
    fi
    CREDS=$(curl -s $NS_HDR -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$AWS_SECRET_PATH")
    AWS_ACCESS_KEY=$(echo "$CREDS" | grep -o '"access_key":"[^"]*' | cut -d'"' -f4 || true)
    AWS_SECRET=$(echo "$CREDS" | grep -o '"secret_key":"[^"]*' | cut -d'"' -f4 || true)
    if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET" ]; then
      log "Vault did not return expected keys"
      return 1
    fi
    mask "$AWS_ACCESS_KEY"
    mask "$AWS_SECRET"
    write_output aws_access_key_id "$AWS_ACCESS_KEY"
    write_output aws_secret_access_key "$AWS_SECRET"
    write_output aws_region "us-east-1"
    log "Fetched credentials from Vault"
    return 0
  else
    log "No AppRole credentials present for Vault fetch"
    return 1
  fi
}

main() {
  if [ "$PREFERENCE" = "VAULT" ]; then
    log "Preference=VAULT: trying Vault first"
    if fetch_from_vault; then
      return 0
    fi
    log "Vault attempt failed — falling back to GSM"
    if fetch_from_gsm; then
      return 0
    fi
    log "Both Vault and GSM failed"
    return 1
  else
    log "Preference=GSM: trying GSM first"
    if fetch_from_gsm; then
      return 0
    fi
    log "GSM attempt failed — falling back to Vault"
    if fetch_from_vault; then
      return 0
    fi
    log "Both GSM and Vault failed"
    return 1
  fi
}

main
