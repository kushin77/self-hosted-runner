#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <image>"
  exit 2
fi
IMAGE="$1"
SBOM_FILE="sbom-$(echo "$IMAGE" | tr '/:' '__').json"

# Ensure syft and cosign available in runner environment.
# Prefer: `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh` or use syft GitHub action.

if ! command -v syft >/dev/null 2>&1; then
  echo "syft not found; installing to /usr/local/bin"
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign not found; installing"
  COSIGN_VERSION="2.1.0"
  curl -sSfL https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64 -o /usr/local/bin/cosign
  chmod +x /usr/local/bin/cosign
fi

# Produce SBOM
echo "Generating SBOM for $IMAGE -> $SBOM_FILE"
syft "$IMAGE" -o json > "$SBOM_FILE"

# Acquire signing key: prefer VAULT (example), or env COSIGN_PRIVATE_KEY
if [ -n "${VAULT_ADDR:-}" ]; then
  if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Vault token not present; try vault_oidc_login.sh beforehand"
    # caller should ensure VAULT_TOKEN exists
  fi
  # Example: secret at secret/data/cosign, field key
  if [ -n "${VAULT_TOKEN:-}" ]; then
    KEY_JSON=$(curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/cosign" ) || true
    COSIGN_KEY=$(echo "$KEY_JSON" | jq -r '.data.data.key // empty') || true
    if [ -n "$COSIGN_KEY" ]; then
      echo "$COSIGN_KEY" > cosign.key
      export COSIGN_PASSWORD=""
      chmod 600 cosign.key
      echo "Signing SBOM with cosign (private key from Vault)"
      cosign sign-blob --key cosign.key "$SBOM_FILE"
    fi
  fi
fi

# Fallback: if COSIGN_PRIVATE_KEY env provided as base64
if [ -z "${COSIGN_KEY:-}" ]; then
  if [ -n "${COSIGN_PRIVATE_KEY:-}" ]; then
    echo "$COSIGN_PRIVATE_KEY" | base64 -d > cosign.key
    chmod 600 cosign.key
    cosign sign-blob --key cosign.key "$SBOM_FILE"
  else
    echo "No signing key found; creating unsigned SBOM artifact"
  fi
fi

echo "SBOM written: $SBOM_FILE"
