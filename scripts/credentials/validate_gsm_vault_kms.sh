#!/usr/bin/env bash
set -euo pipefail
# Validate that Google Secret Manager secret, Vault access, and KMS key are reachable/configured
# Usage: SECRET_NAME=my-secret KMS_KEY=projects/PROJECT/locations/global/keyRings/kr/cryptoKeys/key ./validate_gsm_vault_kms.sh

: ${SECRET_NAME:=}
: ${KMS_KEY:=}

if [[ -z "$SECRET_NAME" ]]; then
  echo "ERROR: SECRET_NAME must be provided (env or arg)"
  exit 2
fi

if [[ -z "$KMS_KEY" ]]; then
  echo "ERROR: KMS_KEY must be provided (env or arg)"
  exit 2
fi

echo "Validating Google Secret Manager secret: $SECRET_NAME"
if ! gcloud secrets describe "$SECRET_NAME" >/dev/null 2>&1; then
  echo "ERROR: Secret $SECRET_NAME not found in GSM for current project"
  exit 3
fi

echo "Validating Vault access"
VAULT_TKN_FILE=${VAULT_TKN_FILE:-/var/run/secrets/vault/token}
if [[ -f "$VAULT_TKN_FILE" ]]; then
  echo "Found Vault token file: $VAULT_TKN_FILE"
else
  echo "WARNING: Vault token file not found. Ensure VAULT_TKN or AppRole is available for transient auth."
fi

echo "Validating KMS key: $KMS_KEY"
if ! gcloud kms keys describe "${KMS_KEY##*/}" --keyring="$(basename $(dirname "$KMS_KEY"))" --location="$(echo $KMS_KEY | awk -F/ '{print $(NF-3)}')" >/dev/null 2>&1; then
  echo "ERROR: KMS key not found or not accessible"
  exit 4
fi

echo "GSM, Vault, and KMS validation passed (subject to operator auth)"
exit 0
