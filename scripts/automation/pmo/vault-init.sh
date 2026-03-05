#!/bin/sh
set -eo pipefail

# Vault initialization script for immutable ephemeral instances
# Starts Vault in dev mode with AppRole pre-configured

ROOT_TOKEN="${VAULT_DEV_ROOT_TOKEN_ID:-vault-dev-root-$(openssl rand -hex 8)}"
export VAULT_DEV_ROOT_TOKEN_ID="$ROOT_TOKEN"
export VAULT_DEV_LISTEN_ADDRESS="${VAULT_DEV_LISTEN_ADDRESS:-0.0.0.0:8200}"
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="$ROOT_TOKEN"

# Write credentials to a temp location accessible from host
CREDS_DIR="/tmp/vault-creds"
mkdir -p "$CREDS_DIR"

echo "[init] Starting Vault v$(vault version | head -n1) in dev mode"
echo "[init] Root Token: $ROOT_TOKEN"
echo "[init] Listen address: $VAULT_DEV_LISTEN_ADDRESS"

# Start Vault in dev mode with AppRole auth enabled
vault server -dev \
  -dev-root-token-id="$ROOT_TOKEN" \
  -dev-listen-address="$VAULT_DEV_LISTEN_ADDRESS" \
  -dev-auth-enable=approle &

VAULT_PID=$!

# Wait for Vault to be ready
echo "[init] Waiting for Vault to start..."
MAX_ATTEMPTS=60
ATTEMPT=0
while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
  if curl -sS --fail "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
    echo "[init] ✓ Vault is ready"
    break
  fi
  sleep 1
  ATTEMPT=$((ATTEMPT + 1))
done

if [ "$ATTEMPT" -eq "$MAX_ATTEMPTS" ]; then
  echo "[init] ERROR: Vault failed to start after $MAX_ATTEMPTS seconds" >&2
  exit 1
fi

# Create runner policy
echo "[init] Creating runner policy..."
cat > /tmp/runner-policy.hcl <<'POLICY'
path "secret/data/runner/*" {
  capabilities = ["read"]
}
POLICY

vault policy write runner-policy /tmp/runner-policy.hcl

# Create AppRole for runner
echo "[init] Creating runner AppRole..."
vault write auth/approle/role/runner \
  token_policies="runner-policy" \
  token_ttl=1h \
  token_max_ttl=4h

# Generate and retrieve credentials
echo "[init] Generating AppRole credentials..."
ROLE_ID=$(vault read -format=json auth/approle/role/runner/role-id | jq -r .data.role_id)
SECRET_JSON=$(vault write -format=json -f auth/approle/role/runner/secret-id)
SECRET_ID=$(echo "$SECRET_JSON" | jq -r .data.secret_id)

# Export credentials to accessible location
printf "%s" "$ROOT_TOKEN" > "$CREDS_DIR/root-token.txt"
printf "%s" "$ROLE_ID" > "$CREDS_DIR/role-id.txt"
printf "%s" "$SECRET_ID" > "$CREDS_DIR/secret-id.txt"
chmod 600 "$CREDS_DIR"/*

echo "[init] ✓ AppRole configured"
echo "[init] ✓ Credentials written to $CREDS_DIR"
echo "[init] ✓ Role ID: $ROLE_ID"

# Wait for Vault process to continue running
wait $VAULT_PID
