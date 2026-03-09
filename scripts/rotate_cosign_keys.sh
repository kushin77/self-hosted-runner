#!/usr/bin/env bash
set -euo pipefail

# Rotate cosign keypair and store in Vault at secret/data/cosign
# Requires: VAULT_ADDR and VAULT_TOKEN in env (or use vault_oidc_login.sh to obtain)

COSIGN_BIN=${COSIGN_BIN:-cosign}
VAULT_ADDR=${VAULT_ADDR:-}
VAULT_PATH=${VAULT_PATH:-secret/data/cosign}

if ! command -v "$COSIGN_BIN" >/dev/null 2>&1; then
  echo "cosign not found; please install cosign"
  exit 2
fi

TMPDIR=$(mktemp -d)
pushd "$TMPDIR"

# Generate key pair
${COSIGN_BIN} generate-key-pair
# This creates cosign.key and cosign.pub
if [ ! -f cosign.key ] || [ ! -f cosign.pub ]; then
  echo "Key generation failed"
  exit 3
fi

# Store in Vault
if [ -n "$VAULT_ADDR" ] && [ -n "${VAULT_TOKEN:-}" ]; then
  echo "Storing cosign keys in Vault at $VAULT_PATH"
  # Use KV v2 data structure
  curl -sS -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H 'Content-Type: application/json' \
    --data "{\"data\":{\"key\":\"$(awk '{printf "%s\\n", $0}' cosign.key | sed 's/\\/\\\\/g' | awk '{printf "%s\\n", $0}' | jq -s -R -r @json)\",\"pub\":\"$(awk '{printf "%s\\n", $0}' cosign.pub | sed 's/\\/\\\\/g' | jq -s -R -r @json)\"}}" \
    "$VAULT_ADDR/v1/$VAULT_PATH" > /dev/null
  echo "Stored in Vault"
else
  echo "VAULT_ADDR/VAULT_TOKEN not present; skipping Vault storage. Keys available in $TMPDIR"
fi

popd

echo "Cosign key rotation complete. Private key location: $TMPDIR/cosign.key (cleanup/rotate as needed)"
