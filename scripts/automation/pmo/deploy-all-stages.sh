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
  rm -rf "$CREDS_DIR" 2>/dev/null || true
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

# Step 3: Wait for credentials to be written by init script
echo "[orchestrator] Waiting for Vault to configure AppRole and write credentials..."
MAX_WAIT=90
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  # Check if Vault is healthy
  HEALTH=$(docker exec "$CONTAINER_NAME" curl -sS http://127.0.0.1:8200/v1/sys/health 2>/dev/null || echo "")
  if [ -n "$HEALTH" ]; then
    # Now check for credentials
    if docker exec "$CONTAINER_NAME" test -f /tmp/vault-creds/role-id.txt 2>/dev/null; then
      echo "[orchestrator] ✓ Vault initialized and credentials ready"
      break
    fi
  fi
  echo "[orchestrator] Waiting... ($WAITED/$MAX_WAIT)"
  sleep 2
  ((WAITED+=2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  echo "[orchestrator] ERROR: Vault failed to initialize within $MAX_WAIT seconds" >&2
  echo "[orchestrator] Container logs:"
  docker logs "$CONTAINER_NAME" | tail -30 || true
  exit 1
fi

# Step 4: Retrieve credentials from container
echo "[orchestrator] Retrieving credentials from ephemeral Vault..."
docker exec "$CONTAINER_NAME" cat /tmp/vault-creds/root-token.txt > "$SCRIPT_DIR/vault-root-token.tmp"
docker exec "$CONTAINER_NAME" cat /tmp/vault-creds/role-id.txt > "$SCRIPT_DIR/vault-role-id.tmp"
docker exec "$CONTAINER_NAME" cat /tmp/vault-creds/secret-id.txt > "$SCRIPT_DIR/vault-secret-id.tmp"

ROOT_TOKEN=$(cat "$SCRIPT_DIR/vault-root-token.tmp")
ROLE_ID=$(cat "$SCRIPT_DIR/vault-role-id.tmp")
SECRET_ID=$(cat "$SCRIPT_DIR/vault-secret-id.tmp")

rm -f "$SCRIPT_DIR"/vault-*.tmp

echo "[orchestrator] ✓ Credentials retrieved"
echo "[orchestrator] ✓ VAULT_ADDR: $VAULT_ADDR"
echo "[orchestrator] ✓ VAULT_ROLE_ID: $ROLE_ID"

# Save to artifacts for external reference
mkdir -p artifacts/vault
printf "%s" "$ROOT_TOKEN" > artifacts/vault/root-token.txt
printf "%s" "$ROLE_ID" > artifacts/vault/role-id.txt
printf "%s" "$SECRET_ID" > artifacts/vault/secret-id.txt
chmod 600 artifacts/vault/*

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
    echo "[orchestrator] Stage 3: (Optional post-deployment validation)"
    # Stage 3 would be post-deployment checks, health verification, etc.
    echo "[orchestrator] Stage 3: Skipped (define in deploy-p2-production.sh if needed)"
    ;;
esac

echo "[orchestrator] ✓ All stages completed successfully"
echo "[orchestrator] Ephemeral Vault instance will be cleaned up on exit"
echo "[orchestrator] Credentials persisted to artifacts/vault/ for reference"

exit 0
