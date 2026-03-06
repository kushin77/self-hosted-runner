#!/usr/bin/env bash
set -euo pipefail
# Fetch a secret value from Vault and optionally export it as an env var
# Usage: VAULT_ADDR=... VAULT_TOKEN=... ./ci/scripts/fetch-vault-secret.sh secret/path field [ENV_VAR_NAME]

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <secret/path> <field> [ENV_VAR_NAME]" >&2
  exit 2
fi

SECRET_PATH=$1
FIELD=$2
ENV_VAR_NAME=${3:-}

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
  echo "VAULT_ADDR and VAULT_TOKEN must be set in the environment" >&2
  exit 2
fi

echo "Fetching secret ${SECRET_PATH}#${FIELD} from Vault..."
RESP=$(curl -sS --fail -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/${SECRET_PATH}")
if [ -z "$RESP" ]; then
  echo "Empty response from Vault" >&2
  exit 3
fi

VALUE=$(echo "$RESP" | jq -r ".data.data.${FIELD} // .data.${FIELD} // empty")
if [ -z "$VALUE" ]; then
  echo "Field '${FIELD}' not found in Vault response" >&2
  exit 4
fi

if [ -n "$ENV_VAR_NAME" ]; then
  echo "Exporting secret to env var ${ENV_VAR_NAME}"
  # shellcheck disable=SC2086
  export ${ENV_VAR_NAME}="${VALUE}"
  # Also print to stdout in a safe manner for CI to pick up (but not exposing in logs)
  echo "${ENV_VAR_NAME} set"
else
  # Print value to stdout (CI runner should capture as needed)
  printf '%s' "$VALUE"
fi
