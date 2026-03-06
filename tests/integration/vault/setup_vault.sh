#!/usr/bin/env bash
set -euo pipefail
# Wait for Vault to be ready and write a sample runner token into KV v2
VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}
VAULT_TOKEN=${VAULT_TOKEN:-devroot}
SECRET_PATH=${SECRET_PATH:-secret/data/ci/self-hosted/test-runner}
REG_TOKEN=${REG_TOKEN:-test-registration-token}

# wait up to 30s for vault
for i in {1..15}; do
  if curl -sSf --max-time 2 "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# write KV v2 secret
curl -sSf -X POST --header "X-Vault-Token: $VAULT_TOKEN" --header "Content-Type: application/json" \
  --data "{\"data\": {\"token\": \"$REG_TOKEN\"}}" \
  "$VAULT_ADDR/v1/${SECRET_PATH}"

echo "Wrote secret to $SECRET_PATH"
