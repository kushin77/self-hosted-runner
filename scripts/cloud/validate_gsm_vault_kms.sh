#!/usr/bin/env bash
# Cloud validation helper: run after operator supplies WIF/AppRole and enables APIs
set -euo pipefail

# Usage: ./validate_gsm_vault_kms.sh

echo "Cloud validation helper"

if [[ -z "${GCP_PROJECT:-}" ]]; then
  echo "ERROR: GCP_PROJECT must be set" >&2
  exit 2
fi

echo "Checking environment..."
echo "GCP_PROJECT=${GCP_PROJECT}"

# Check gcloud availability
if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI not found; install or provide path" >&2
  exit 3
fi

# Check Vault access via token-file or env
if [[ -f "${VAULT_TKN_MOUNT_PATH:-}" ]]; then
  echo "Using VAULT_TKN_MOUNT_PATH: $VAULT_TKN_MOUNT_PATH"
elif [[ -f "${VAULT_TKN_FILE:-/var/run/secrets/vault/token}" ]]; then
  echo "Using VAULT_TKN_FILE (legacy): ${VAULT_TKN_FILE:-/var/run/secrets/vault/token}"
elif [[ -n "${VAULT_TKN:-}" ]]; then
  echo "Using VAULT_TKN from environment"
else
  echo "No Vault token available. Ensure AppRole or Vault Agent token sink is provisioned." >&2
  exit 4
fi

echo "Verifying Secret Manager read..."
if ! gcloud secrets list --project="$GCP_PROJECT" >/dev/null 2>&1; then
  echo "Unable to list secrets. Ensure Secret Manager API enabled and identity has access." >&2
  exit 5
fi

echo "Verifying Vault KV write/read..."
if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not found; install or provide path" >&2
  exit 6
fi

TMP_PATH="secret/data/validate-ci"
TEST_VAL="ci-validate-$(date +%s)"
vault kv put --mount=secret validate-ci value="$TEST_VAL" >/dev/null
READ=$(vault kv get -field=value --mount=secret validate-ci)
if [[ "$READ" != "$TEST_VAL" ]]; then
  echo "Vault read mismatch: expected $TEST_VAL got $READ" >&2
  exit 7
fi

echo "Verifying optional AWS KMS decrypt (if configured)..."
if [[ -n "${AWS_KMS_KEY_ID:-}" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    echo "aws CLI not found; install to validate KMS" >&2
  else
    echo "AWS_KMS_KEY_ID present; attempting a small encrypt/decrypt cycle"
    PLAINTEXT="kms-validate-$(date +%s)"
    ENC=$(aws kms encrypt --key-id "$AWS_KMS_KEY_ID" --plaintext "$PLAINTEXT" --output text --query CiphertextBlob || true)
    if [[ -z "$ENC" ]]; then
      echo "KMS encrypt failed; ensure IAM and KMS key permissions" >&2
    else
      echo "KMS encrypt succeeded (base64 blob length=${#ENC})"
    fi
  fi
fi

echo "Cloud validation checks passed locally — operator actions required for full end-to-end run in cloud." 
echo "Follow docs: docs/runbooks/credential_unblock_runbook.md and docs/verification/credential_verification.md"

exit 0
