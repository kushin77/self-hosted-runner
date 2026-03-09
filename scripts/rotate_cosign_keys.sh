#!/usr/bin/env bash
set -euo pipefail

# Rotate cosign keypair and store in Vault at secret/data/cosign/keys
# Requires: VAULT_ADDR and VAULT_TOKEN in env (or use vault_oidc_login.sh to obtain)

COSIGN_BIN=${COSIGN_BIN:-cosign}
VAULT_ADDR=${VAULT_ADDR:-}
VAULT_TOKEN=${VAULT_TOKEN:-}
VAULT_PATH=${VAULT_PATH:-secret/data/cosign/keys}

if ! command -v "$COSIGN_BIN" >/dev/null 2>&1; then
  echo "Installing cosign..."
  COSIGN_VERSION="2.1.0"
  curl -sSfL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" -o /tmp/cosign
  chmod +x /tmp/cosign
  COSIGN_BIN=/tmp/cosign
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

pushd "$TMPDIR"

echo "Generating cosign key pair..."
${COSIGN_BIN} generate-key-pair --answer-security-questions=false || true

if [ ! -f cosign.key ] || [ ! -f cosign.pub ]; then
  echo "ERROR: Key generation failed"
  exit 3
fi

echo "Key pair generated successfully"

if [ -n "$VAULT_ADDR" ] && [ -n "$VAULT_TOKEN" ]; then
  echo "Storing cosign keys in Vault at $VAULT_PATH..."
  PRIVATE_KEY_B64=$(base64 -w0 < cosign.key)
  PUBLIC_KEY_B64=$(base64 -w0 < cosign.pub)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  RESPONSE=$(curl -sS -w "\n%{http_code}" -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H 'Content-Type: application/json' \
    --data "{
      \"data\": {
        \"private_key_b64\": \"$PRIVATE_KEY_B64\",
        \"public_key_b64\": \"$PUBLIC_KEY_B64\",
        \"rotated_at\": \"$TIMESTAMP\"
      }
    }" \
    "$VAULT_ADDR/v1/$VAULT_PATH")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)
  
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
    echo "✓ Keys stored in Vault successfully"
  else
    echo "ERROR: Vault storage failed (HTTP $HTTP_CODE): $BODY"
    exit 4
  fi
else
  echo "WARN: VAULT_ADDR/VAULT_TOKEN not set; keys available locally in $TMPDIR"
fi

echo "Cosign key rotation complete"
echo "Public key: $TMPDIR/cosign.pub"

popd
