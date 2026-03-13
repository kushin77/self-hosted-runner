#!/usr/bin/env bash
set -euo pipefail

# Helper to rotate Vault AppRole secret_id using VAULT_ADDR/VAULT_TOKEN from
# environment or Google Secret Manager. Does NOT store tokens in repo or logs.

GSM_PROJECT=${GSM_PROJECT:-nexusshield-prod}
LOG=logs/rotate-vault-$(date -u +%Y%m%dT%H%M%SZ).log
exec > >(tee -a "$LOG") 2>&1

echo "Starting Vault AppRole rotation at $(date -u)"

get_secret() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    echo "Using env $name"
    echo "${!name}"
    return 0
  fi
  if command -v gcloud >/dev/null 2>&1; then
    if gcloud secrets versions access latest --secret="$name" --project="$GSM_PROJECT" >/dev/null 2>&1; then
      gcloud secrets versions access latest --secret="$name" --project="$GSM_PROJECT"
      return 0
    fi
  fi
  return 1
}

if [[ -n "${VAULT_ADDR:-}" ]]; then
  VAULT_ADDR_RAW="${VAULT_ADDR}"
else
  VAULT_ADDR_RAW=$(get_secret VAULT_ADDR || true)
fi

if [[ -n "${VAULT_TOKEN:-}" ]]; then
  VAULT_TOKEN_RAW="${VAULT_TOKEN}"
else
  VAULT_TOKEN_RAW=$(get_secret VAULT_TOKEN || true)
fi

if [[ -z "$VAULT_ADDR_RAW" || -z "$VAULT_TOKEN_RAW" ]]; then
  echo "ERROR: VAULT_ADDR and VAULT_TOKEN must be provided via env or Secret Manager" >&2
  exit 1
fi

# Detect obvious placeholders
if [[ "$VAULT_ADDR_RAW" =~ PLACEHOLDER|example|your-vault ]]; then
  echo "ERROR: VAULT_ADDR appears to be a placeholder: $VAULT_ADDR_RAW" >&2
  exit 1
fi
if [[ "$VAULT_TOKEN_RAW" =~ PLACEHOLDER|REDACTED ]]; then
  echo "ERROR: VAULT_TOKEN appears to be a placeholder" >&2
  exit 1
fi

VAULT_ADDR="$VAULT_ADDR_RAW"
VAULT_TOKEN="$VAULT_TOKEN_RAW"

echo "Checking Vault health at $VAULT_ADDR"
if ! curl -sfS --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/health" >/dev/null; then
  echo "ERROR: cannot contact Vault at $VAULT_ADDR with provided token" >&2
  exit 1
fi

echo "Requesting new AppRole secret_id"
NEW_SECRET_ID=$(curl -sS --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/approle/role/example-role/secret-id" | jq -r '.data.secret_id' || true)
if [[ -z "$NEW_SECRET_ID" || "$NEW_SECRET_ID" == "null" ]]; then
  echo "ERROR: failed to obtain new secret_id from Vault API" >&2
  exit 1
fi

echo "Storing new secret_id into GSM secret 'vault-example-role-secret_id'"
if [[ -n "${GSM_PROJECT:-}" ]]; then
  echo -n "$NEW_SECRET_ID" | gcloud secrets versions add vault-example-role-secret_id --data-file=- --project="$GSM_PROJECT"
  echo "Stored new version in GSM"
else
  echo "GSM_PROJECT not set; aborting" >&2
  exit 1
fi

echo "Vault AppRole rotation completed successfully"
echo "Log saved to $LOG"
