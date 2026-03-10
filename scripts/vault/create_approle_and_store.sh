#!/usr/bin/env bash
set -euo pipefail

# Create a Vault AppRole and store role_id and secret_id in Google Secret Manager
# Usage: VAULT_ROLE_NAME=automation-runner ROLE_SECRET_NAME=automation-runner-vault-secret-id ROLE_ID_SECRET_NAME=automation-runner-vault-role-id PROJECT=nexusshield-prod ./create_approle_and_store.sh

VAULT_ROLE_NAME=${VAULT_ROLE_NAME:-automation-runner}
ROLE_SECRET_NAME=${ROLE_SECRET_NAME:-automation-runner-vault-secret-id}
ROLE_ID_SECRET_NAME=${ROLE_ID_SECRET_NAME:-automation-runner-vault-role-id}
PROJECT=${PROJECT:-}

if [[ -z "$PROJECT" ]]; then
  echo "ERROR: PROJECT env is required"
  exit 2
fi

if ! command -v vault >/dev/null 2>&1; then
  echo "ERROR: vault CLI not found"
  exit 3
fi
if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud CLI not found"
  exit 4
fi

echo "Creating AppRole '$VAULT_ROLE_NAME' in Vault"
vault write auth/approle/role/${VAULT_ROLE_NAME} token_ttl=1h token_max_ttl=1h >/dev/null

echo "Fetching role_id"
ROLE_ID=$(vault read -format=json auth/approle/role/${VAULT_ROLE_NAME}/role-id | jq -r .data.role_id)

echo "Generating secret_id"
SECRET_ID=$(vault write -format=json -f auth/approle/role/${VAULT_ROLE_NAME}/secret-id | jq -r .data.secret_id)

echo "Storing role_id in Secret Manager: ${ROLE_ID_SECRET_NAME}"
echo -n "$ROLE_ID" | gcloud secrets versions add "${ROLE_ID_SECRET_NAME}" --data-file=- --project="$PROJECT"

echo "Storing secret_id in Secret Manager: ${ROLE_SECRET_NAME}"
echo -n "$SECRET_ID" | gcloud secrets versions add "${ROLE_SECRET_NAME}" --data-file=- --project="$PROJECT"

echo "AppRole created and stored in Secret Manager"
echo "Role: $VAULT_ROLE_NAME"
echo "Role Secret Name: $ROLE_SECRET_NAME"
echo "Role ID Secret Name: $ROLE_ID_SECRET_NAME"

exit 0
