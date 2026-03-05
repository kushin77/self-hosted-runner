#!/usr/bin/env bash
set -euo pipefail

# Prototype: Vault OIDC bootstrapper for short-lived registry credentials
# - Assumes a Vault JWT/OIDC auth endpoint at $VAULT_ADDR
# - Requires an ID token from your IdP available as $ID_TOKEN (or use local helper)
# - Reads registry credentials from KV path: secret/data/registries/staging

if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_ROLE:-}" ]]; then
  echo "Error: VAULT_ADDR and VAULT_ROLE must be set in the environment."
  echo "Example: export VAULT_ADDR=https://vault.example.com export VAULT_ROLE=runner-role"
  exit 1
fi

if [[ -z "${ID_TOKEN:-}" ]]; then
  echo "Error: ID_TOKEN (OIDC JWT) is required for prototype login. Acquire from your IdP."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: 'jq' not found. Install jq for robust JSON parsing." >&2
fi

echo "Logging into Vault ($VAULT_ADDR) using OIDC role: $VAULT_ROLE"
resp=$(curl -fsS -X POST -d "{\"role\": \"${VAULT_ROLE}\", \"jwt\": \"${ID_TOKEN}\"}" "${VAULT_ADDR}/v1/auth/jwt/login")
VAULT_TOKEN=$(echo "$resp" | jq -r '.auth.client_token // empty')

if [[ -z "$VAULT_TOKEN" ]]; then
  echo "Vault login failed. Response:" >&2
  echo "$resp" >&2
  exit 2
fi

export VAULT_TOKEN
echo "Vault login successful; VAULT_TOKEN exported for this session."

# Fetch registry credentials (example KV path: secret/data/registries/staging)
echo "Fetching registry credentials from Vault (secret/data/registries/staging)"
reg=$(curl -fsS --header "X-Vault-Token: $VAULT_TOKEN" "${VAULT_ADDR}/v1/secret/data/registries/staging")
REG_USER=$(echo "$reg" | jq -r '.data.data.username // empty')
REG_PASS=$(echo "$reg" | jq -r '.data.data.password // empty')

if [[ -z "$REG_USER" || -z "$REG_PASS" ]]; then
  echo "Registry credentials not found at secret/data/registries/staging" >&2
  echo "Returned payload: $reg" >&2
  exit 3
fi

echo "Logging into registry (username: $REG_USER)"
echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ${TARGET_REGISTRY:-registry-staging.example.com}

echo "✓ Docker login succeeded (registry: ${TARGET_REGISTRY:-registry-staging.example.com})."
echo "NOTE: This is a prototype. Replace direct KV reads with short-lived Vault leases and rotate accordingly."

exit 0
