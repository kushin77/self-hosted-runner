#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <image>"
  exit 2
fi
IMAGE="$1"
SBOM_FILE="sbom-$(echo "$IMAGE" | tr '/:' '__').json"
SIG_FILE="${SBOM_FILE}.sig"

if [ ! -f "$SBOM_FILE" ]; then
  echo "SBOM file $SBOM_FILE not found"
  exit 3
fi

if [ ! -f "$SIG_FILE" ]; then
  echo "Signature file $SIG_FILE not found"
  exit 4
fi

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign not found; attempting install"
  COSIGN_VERSION="2.1.0"
  curl -sSfL https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64 -o /usr/local/bin/cosign
  chmod +x /usr/local/bin/cosign
fi

# Acquire public key from VAULT or env
if [ -n "${VAULT_ADDR:-}" ] && [ -n "${VAULT_TOKEN:-}" ]; then
  PUB_JSON=$(curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/cosign_pub" || true)
  PUB_KEY=$(echo "$PUB_JSON" | jq -r '.data.data.key // empty') || true
  if [ -n "$PUB_KEY" ]; then
    echo "$PUB_KEY" > cosign.pub
  fi
fi

if [ -n "${COSIGN_PUBLIC_KEY:-}" ]; then
  echo "$COSIGN_PUBLIC_KEY" > cosign.pub
fi

if [ ! -f cosign.pub ]; then
  echo "No public key available to verify signature"
  exit 5
fi

cosign verify-blob --key cosign.pub "$SBOM_FILE"
echo "SBOM signature verified"
