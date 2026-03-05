#!/usr/bin/env bash
set -euo pipefail

# Ephemeral Vault bootstrapper
# - Runs a Vault dev container (ephemeral, --rm) bound to host 8200
# - Creates a minimal policy and an AppRole for the runner
# - Writes Role ID and Secret ID to `artifacts/vault/` with restricted perms

ROOT_DIR="$(pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/vault"
mkdir -p "${ARTIFACT_DIR}"

IMAGE="hashicorp/vault:1.15.4"
CONTAINER_NAME="vault-ephemeral-$$"
VAULT_ADDR="http://127.0.0.1:8200"
ROOT_TOKEN_FILE="${ARTIFACT_DIR}/vault-root-token.txt"
ROLE_ID_FILE="${ARTIFACT_DIR}/vault-approle-role-id.txt"
SECRET_ID_FILE="${ARTIFACT_DIR}/vault-approle-secret-id.txt"

ROOT_TOKEN="$(openssl rand -hex 16)"

echo "Starting ephemeral Vault container (${CONTAINER_NAME})..."
docker run --rm -d --name "${CONTAINER_NAME}" -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID="${ROOT_TOKEN}" \
  -e VAULT_DEV_LISTEN_ADDRESS="0.0.0.0:8200" \
  "${IMAGE}" server -dev -dev-root-token-id="${ROOT_TOKEN}"

echo "Waiting for Vault to become ready at ${VAULT_ADDR}..."
for i in {1..30}; do
  if curl -sS --fail "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
    echo "Vault is ready"
    break
  fi
  sleep 1
done

if ! curl -sS --fail "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
  echo "Vault did not become ready" >&2
  docker logs "${CONTAINER_NAME}" || true
  exit 1
fi

export VAULT_ADDR
export VAULT_TOKEN="${ROOT_TOKEN}"

echo "Root token written to ${ROOT_TOKEN_FILE} (restricted perms)"
printf "%s" "${ROOT_TOKEN}" > "${ROOT_TOKEN_FILE}"
chmod 600 "${ROOT_TOKEN_FILE}"

echo "Enabling AppRole auth and creating policy..."
vault auth enable approle || true

POLICY_NAME=runner-policy
cat > /tmp/${POLICY_NAME}.hcl <<'EOF'
path "secret/data/runner/*" {
  capabilities = ["read"]
}
EOF

vault policy write "${POLICY_NAME}" /tmp/${POLICY_NAME}.hcl

ROLE_NAME=runner
echo "Creating AppRole '${ROLE_NAME}' with policy ${POLICY_NAME}..."
vault write auth/approle/role/${ROLE_NAME} token_policies="${POLICY_NAME}" token_ttl=1h token_max_ttl=4h

echo "Fetching RoleID and SecretID..."
ROLE_ID=$(vault read -format=json auth/approle/role/${ROLE_NAME}/role-id | jq -r .data.role_id)
SECRET_ID_JSON=$(vault write -format=json -f auth/approle/role/${ROLE_NAME}/secret-id)
SECRET_ID=$(echo "${SECRET_ID_JSON}" | jq -r .data.secret_id)

printf "%s" "${ROLE_ID}" > "${ROLE_ID_FILE}"
printf "%s" "${SECRET_ID}" > "${SECRET_ID_FILE}"
chmod 600 "${ROLE_ID_FILE}" "${SECRET_ID_FILE}"

echo "AppRole created. Role ID -> ${ROLE_ID_FILE}, Secret ID -> ${SECRET_ID_FILE}"

echo "Bootstrap complete. Stage 2 deploy can now use VAULT_ADDR=${VAULT_ADDR} and VAULT_TOKEN stored in ${ROOT_TOKEN_FILE}" 

echo "Note: this Vault instance is ephemeral. Stop the container to remove state: docker stop ${CONTAINER_NAME}" 

exit 0
