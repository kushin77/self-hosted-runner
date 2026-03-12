#!/usr/bin/env bash
set -euo pipefail
# Fetch a secret from HashiCorp Vault and write GH_TOKEN to stdout or file
# Usage: vault_fetch_token.sh <vault_path> [out_file]

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <vault_path> [out_file]" >&2
  exit 2
fi
VAULT_PATH="$1"
OUT_FILE="${2:-}"

if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not installed; cannot fetch secret" >&2
  exit 1
fi

TOKEN=$(vault kv get -field=token "$VAULT_PATH")

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf '%s' "$TOKEN" > "$OUT_FILE"
  chmod 600 "$OUT_FILE"
else
  printf '%s' "$TOKEN"
fi
