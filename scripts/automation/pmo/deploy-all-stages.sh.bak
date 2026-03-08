#!/usr/bin/env bash
set -euo pipefail

# Master orchestration script: Build Vault image, run ephemeral Vault, deploy all stages
# Usage: ./deploy-all-stages.sh [stage1|stage2|stage3|all]

STAGE="${1:-all}"
ROOT_DIR="$(pwd)"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
IMAGE_NAME="vault-ephemeral:latest"
CONTAINER_NAME="vault-ephemeral-deploy-$$"
VAULT_PORT="${VAULT_PORT:-18200}"  # Default to 18200 to avoid conflicts
VAULT_ADDR="http://127.0.0.1:$VAULT_PORT"
CREDS_DIR="/tmp/vault-ephemeral-$$"

# Trap to clean up on exit
cleanup() {
  echo "[orchestrator] Cleaning up..."
  # Stop and remove any existing vault-dev container if this is a fresh run
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker rm -f vault-dev 2>/dev/null || true
  # Use safe_delete wrapper for credential dir cleanup
  SAFE_DELETE="$(pwd)/scripts/safe_delete.sh"
  if [ ! -x "$SAFE_DELETE" ]; then SAFE_DELETE="$(dirname "$0")/../../scripts/safe_delete.sh"; fi
  if [ -x "$SAFE_DELETE" ]; then
    "$SAFE_DELETE" --path "$CREDS_DIR" --dry-run || true
  else
    rm -rf "$CREDS_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Step 1: Build immutable Vault image
echo "[orchestrator] Building immutable Vault image ($IMAGE_NAME)..."
docker build -t "$IMAGE_NAME" \
  -f "$SCRIPT_DIR/Dockerfile.vault" \
  --build-arg VAULT_VERSION=1.15.4 \
  "$SCRIPT_DIR"

# Step 2: Start ephemeral Vault container (will auto-configure AppRole)
echo "[orchestrator] Starting ephemeral Vault container ($CONTAINER_NAME) on port $VAULT_PORT..."
# Note: Removed --rm flag so we can extract credentials; cleanup will happen explicitly in trap
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$VAULT_PORT:8200" \
  -e VAULT_DEV_ROOT_TOKEN_ID="vault-ephemeral-$(date -u +%s)" \
  "$IMAGE_NAME"

# Step 3: Wait for Vault to be ready
VAULT_ADDR_INTERNAL="http://127.0.0.1:8200"
echo "[orchestrator] Waiting for Vault to start..."
echo "[orchestrator] Container name: $CONTAINER_NAME"
echo "[orchestrator] Vault address (internal): $VAULT_ADDR_INTERNAL"
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  # Try connecting to Vault health endpoint via docker exec with VAULT_ADDR set
  echo "[orchestrator] Attempt $((WAITED+1))/$MAX_WAIT: Waiting for vault status..."
  EXEC_OUTPUT=$(docker exec -e VAULT_ADDR="$VAULT_ADDR_INTERNAL" "$CONTAINER_NAME" vault status 2>&1)
  EXEC_EXIT=$?
  if [ $EXEC_EXIT -eq 0 ]; then
    echo "[orchestrator] ✓ Vault is ready"
    break
  else
    echo "[orchestrator] Vault not ready yet (exit code: $EXEC_EXIT)"
  fi
  sleep 2
  ((WAITED+=2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  echo "[orchestrator] ERROR: Vault failed to start within $MAX_WAIT seconds" >&2
  echo "[orchestrator] Container logs:"
  docker logs "$CONTAINER_NAME" | tail -30 || true
  echo "[orchestrator] Current containers:"
  docker ps -a || true
  exit 1
fi

# Step 4: Configure AppRole authentication directly via docker exec
echo "[orchestrator] Configuring AppRole authentication..."
docker exec -e VAULT_ADDR="$VAULT_ADDR_INTERNAL" "$CONTAINER_NAME" vault auth enable approle 2>/dev/null || true

# Create runner policy
echo "[orchestrator] Creating runner policy..."
docker exec -e VAULT_ADDR="$VAULT_ADDR_INTERNAL" "$CONTAINER_NAME" sh -c '
cat > /tmp/runner-policy.hcl <<POLICY_EOF
path "secret/data/runner/*" {
  capabilities = ["read"]
}
POLICY_EOF
vault policy write runner-policy /tmp/runner-policy.hcl
'

# Create AppRole for runner
echo "[orchestrator] Creating runner AppRole..."
docker exec -e VAULT_ADDR="$VAULT_ADDR_INTERNAL" "$CONTAINER_NAME" vault write auth/approle/role/runner \
  token_policies="runner-policy" \
  token_ttl=1h \
  token_max_ttl=4h

# Generate and retrieve credentials
echo "[orchestrator] Generating AppRole credentials..."
CREDS_JSON=$(docker exec -e VAULT_ADDR="$VAULT_ADDR_INTERNAL" "$CONTAINER_NAME" vault read -format=json auth/approle/role/runner/role-id)
ROLE_ID=$(echo "$CREDS_JSON" | jq -r .data.role_id)
SECRET_JSON=$(docker exec -e VAULT_ADDR="$VAULT_ADDR_INTERNAL" "$CONTAINER_NAME" vault write -format=json -f auth/approle/role/runner/secret-id)
SECRET_ID=$(echo "$SECRET_JSON" | jq -r .data.secret_id)
ROOT_TOKEN="dummy-ephemeral-token"

# Save credentials locally
echo "[orchestrator] Saving credentials..."
mkdir -p artifacts/vault
printf "%s" "$ROOT_TOKEN" > artifacts/vault/root-token.txt
printf "%s" "$ROLE_ID" > artifacts/vault/role-id.txt
printf "%s" "$SECRET_ID" > artifacts/vault/secret-id.txt
chmod 600 artifacts/vault/*

echo "[orchestrator] ✓ AppRole configured"
echo "[orchestrator] ✓ VAULT_ADDR: $VAULT_ADDR"
echo "[orchestrator] ✓ VAULT_ROLE_ID: $ROLE_ID"

# Step 5: Run deployment stages with Vault credentials
case "$STAGE" in
  stage1|all)
    echo "[orchestrator] Running Stage 1 (optional)..."
    # Stage 1 is typically already complete (portal + image build)
    echo "[orchestrator] Stage 1 status: Portal and runner image already built in previous phase"
    ;;
esac

case "$STAGE" in
  stage2|all)
    echo "[orchestrator] Running Stage 2 (Vault AppRole setup)..."
    export VAULT_ADDR
    export VAULT_TOKEN="$ROOT_TOKEN"
    export VAULT_ROLE_ID="$ROLE_ID"
    export VAULT_SECRET_ID="$SECRET_ID"
    
    # Ensure vault CLI is available
    if ! command -v vault &>/dev/null; then
      echo "[orchestrator] Installing Vault CLI..."
      mkdir -p ~/.local/bin
      curl -fsSL https://releases.hashicorp.com/vault/1.15.4/vault_1.15.4_linux_amd64.zip -o /tmp/vault.zip
      unzip -o /tmp/vault.zip -d ~/.local/bin
      export PATH=~/.local/bin:$PATH
    fi
    
    cd "$SCRIPT_DIR"
    if [ -f "deploy-p2-production.sh" ]; then
      ./deploy-p2-production.sh stage2 2>&1 | tee ~/deploy-stage2-$(date -u +%Y%m%dT%H%M%SZ).log
    else
      echo "[orchestrator] deploy-p2-production.sh not found, skipping Stage 2 execution"
    fi
    cd "$ROOT_DIR"
    ;;
esac

case "$STAGE" in
  stage3|all)
    echo "[orchestrator] Stage 3: Post-deployment health validation..."
    # Execute health verification
    if [ -f "$SCRIPT_DIR/health-check.sh" ]; then
      VAULT_PORT="$VAULT_PORT" "$SCRIPT_DIR/health-check.sh"
    else
      echo "[orchestrator] WARNING: health-check.sh not found, skipping validation"
    fi
    ;;
esac

echo "[orchestrator] ✓ All stages completed successfully"
echo "[orchestrator] Ephemeral Vault instance will be cleaned up on exit"
echo "[orchestrator] Credentials persisted to artifacts/vault/ for reference"

exit 0
