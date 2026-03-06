#!/usr/bin/env bash
set -euo pipefail

# Provision a temporary Vault AppRole (requires VAULT_ADDR + VAULT_ADMIN_TOKEN),
# run the e2e script, then clean up the AppRole and secret_id.

usage(){
  cat <<EOF
Usage: $0 [-p policy_name] [-n approle_name] [-s secret_file]

Requires:
  - VAULT_ADDR
  - VAULT_ADMIN_TOKEN (to create AppRole) OR existing VAULT_ROLE_ID+VAULT_SECRET_ID

This script will:
  1. Create an AppRole with a short-lived `secret_id` and minimal policy.
  2. Export `VAULT_ROLE_ID` and `VAULT_SECRET_ID_PATH` for the e2e script.
  3. Run `scripts/ci/run-e2e-self-hosted-with-vault.sh`.
  4. Revoke the `secret_id` and delete the AppRole.

Options:
  -p policy_name   Vault policy to attach (default: "ci-e2e-temp")
  -n approle_name  AppRole name (default: "ci-temp-approle")
  -s secret_file   Path to write `secret_id` (default: /tmp/vault-e2e-secret-id)
EOF
}

POLICY_NAME="ci-e2e-temp"
APPROLE_NAME="ci-temp-approle"
SECRET_FILE="/tmp/vault-e2e-secret-id"

while getopts ":p:n:s:" opt; do
  case ${opt} in
    p) POLICY_NAME="$OPTARG" ;;
    n) APPROLE_NAME="$OPTARG" ;;
    s) SECRET_FILE="$OPTARG" ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "ERROR: VAULT_ADDR is required." >&2
  exit 2
fi

if [ -z "${VAULT_ADMIN_TOKEN:-}" ]; then
  echo "VAULT_ADMIN_TOKEN missing; if you already have VAULT_ROLE_ID and VAULT_SECRET_ID, set them in the environment and run the e2e script directly." >&2
  exit 3
fi

export VAULT_TOKEN="$VAULT_ADMIN_TOKEN"

echo "[provision] Creating policy '${POLICY_NAME}' if missing..."
cat > /tmp/${POLICY_NAME}.hcl <<'HCL'
path "secret/data/runnercloud/*" {
  capabilities = ["read"]
}
HCL

vault policy write "$POLICY_NAME" /tmp/${POLICY_NAME}.hcl >/dev/null

echo "[provision] Creating AppRole '${APPROLE_NAME}'..."
ROLE_ID=$(vault write -format=json auth/approle/role/${APPROLE_NAME} token_ttl=1h token_max_ttl=2h policies=${POLICY_NAME} -wrap-ttl=60 | jq -r '.wrap_info.token') || true

# If vault server doesn't support wrap here, attempt role-id/secret-id creation directly
if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" = "null" ]; then
  vault write -format=json auth/approle/role/${APPROLE_NAME} policies=${POLICY_NAME} >/dev/null
  ROLE_ID=$(vault read -format=json auth/approle/role/${APPROLE_NAME}/role-id | jq -r .data.role_id)
fi

SECRET_ID_JSON=$(vault write -format=json -f auth/approle/role/${APPROLE_NAME}/secret-id)
SECRET_ID=$(echo "$SECRET_ID_JSON" | jq -r .data.secret_id)

echo "$SECRET_ID" > "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

export VAULT_ROLE_ID="$ROLE_ID"
export VAULT_SECRET_ID_PATH="$SECRET_FILE"

echo "[provision] VAULT_ROLE_ID and secret written to $SECRET_FILE"

echo "[provision] Running e2e script..."
./scripts/ci/run-e2e-self-hosted-with-vault.sh

echo "[provision] Cleaning up: revoke secret_id and delete AppRole"
vault write -force auth/approle/role/${APPROLE_NAME}/secret-id ( >/dev/null 2>&1 ) || true
vault delete auth/approle/role/${APPROLE_NAME} >/dev/null 2>&1 || true
vault policy delete ${POLICY_NAME} >/dev/null 2>&1 || true

rm -f "$SECRET_FILE"

echo "[provision] Done. Rotate or remove any temporary credentials if necessary."
