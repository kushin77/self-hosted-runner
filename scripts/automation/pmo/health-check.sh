#!/bin/sh
set -e

# Configuration
VAULT_PORT=${VAULT_PORT:-18200}
VAULT_ADDR="http://127.0.0.1:$VAULT_PORT"
ARTIFACT_DIR="artifacts/vault"

echo "Checking system health for Phase 2 Deployment..."

# 1. Check Vault Container
if ! docker ps | grep -q "vault-ephemeral"; then
  echo "CRITICAL: vault-ephemeral container is not running"
  exit 1
fi

# 2. Check Vault Status
if ! curl -s -f "$VAULT_ADDR/v1/sys/health" > /dev/null; then
  echo "CRITICAL: Vault health check failed at $VAULT_ADDR"
  exit 1
fi
echo "✓ Vault is healthy"

# 3. Check Artifacts
for f in role-id.txt secret-id.txt root-token.txt; do
  if [ ! -f "$ARTIFACT_DIR/$f" ]; then
    echo "CRITICAL: Missing artifact $f"
    exit 1
  fi
  if [ ! -s "$ARTIFACT_DIR/$f" ]; then
    echo "CRITICAL: Artifact $f is empty"
    exit 1
  fi
done
echo "✓ Artifacts verified in $ARTIFACT_DIR"

# 4. Check Roles (Internal validation via docker exec)
echo "Verifying AppRole configuration..."
# Use dynamic container discovery matching the orchestrator's pattern
CONTAINER_ID=$(docker ps --filter name=vault-ephemeral-deploy --format "{{.ID}}" | head -n 1)
if [ -z "$CONTAINER_ID" ]; then
  echo "CRITICAL: No active 'vault-ephemeral-deploy' container found"
  exit 1
fi
if ! docker exec -e VAULT_ADDR="http://127.0.0.1:8200" "$CONTAINER_ID" vault read auth/approle/role/runner > /dev/null 2>&1; then
  echo "CRITICAL: AppRole 'runner' not found in Vault container $CONTAINER_ID"
  exit 1
fi
echo "✓ AppRole 'runner' verified in container $CONTAINER_ID"

echo "Phase 2 Infrastructure Health: OK"
