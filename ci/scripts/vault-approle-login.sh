#!/usr/bin/env bash
set -euo pipefail
# Minimal AppRole login helper for CI/runners
# Usage: VAULT_ADDR=https://vault.internal ROLE_ID=... SECRET_ID=... ./ci/scripts/vault-approle-login.sh [--out /path/to/tokenfile]

OUT_FILE="/var/run/vault-token"
if [ "${1:-}" = "--out" ] && [ -n "${2:-}" ]; then
  OUT_FILE="$2"
fi

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "VAULT_ADDR must be set" >&2
  exit 2
fi
if [ -z "${ROLE_ID:-}" ] || [ -z "${SECRET_ID:-}" ]; then
  echo "ROLE_ID and SECRET_ID must be set" >&2
  exit 2
fi

echo "Logging into Vault AppRole at ${VAULT_ADDR}"
RESP=$(curl -fsS --request POST --header "Content-Type: application/json" --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" "${VAULT_ADDR}/v1/auth/approle/login")
if [ -z "$RESP" ]; then
  echo "Vault login failed" >&2
  exit 3
fi

TOKEN=$(echo "$RESP" | jq -r '.auth.client_token // empty')
if [ -z "$TOKEN" ]; then
  echo "Could not extract client token" >&2
  echo "$RESP" >&2
  exit 4
fi

mkdir -p "$(dirname "$OUT_FILE")" || true
printf '%s' "$TOKEN" > "$OUT_FILE"
chmod 600 "$OUT_FILE"
echo "Wrote token to ${OUT_FILE}"

# For CI convenience print the token filepath (not the token itself)
echo "TOKEN_FILE=${OUT_FILE}"

exit 0
