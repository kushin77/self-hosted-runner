#!/usr/bin/env bash
set -euo pipefail

# Provision a Vault AppRole and optionally set GitHub repository secrets via `gh`.
# Designed to be run from a secure environment (CI controller or admin workstation).
#
# Usage:
#  VAULT_ADDR=https://vault.example.com VAULT_ADMIN_TOKEN=... GITHUB_REPOSITORY=owner/repo \ 
#    ./scripts/ci/provision-approle-and-set-secrets.sh --role-name runner-deploy --policy-path ./policies/runner-deploy.hcl

GIT_REPO=${GITHUB_REPOSITORY:-}
VAULT_ADDR=${VAULT_ADDR:-}
VAULT_TOKEN=${VAULT_ADMIN_TOKEN:-}
ROLE_NAME=runner-deploy
POLICY_NAME=runner-deploy
POLICY_FILE=""

usage(){
  cat <<EOF
Usage: $0 [--role-name NAME] [--policy-file PATH]

Environment variables:
  VAULT_ADDR           Vault address (required or set env)
  VAULT_ADMIN_TOKEN    Vault admin token with rights to create policies and AppRoles (required)
  GITHUB_REPOSITORY    Optional. If set and `gh` is authenticated, will create repo secrets.

Examples:
  VAULT_ADDR=https://vault.example.com VAULT_ADMIN_TOKEN=
  VAULT_ROLE_ID=... VAULT_SECRET_ID=... $0 --role-name runner-deploy

EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role-name) ROLE_NAME="$2"; shift 2 ;;
    --policy-file) POLICY_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
  echo "VAULT_ADDR and VAULT_ADMIN_TOKEN must be set in environment" >&2
  usage
fi

if [ -n "$POLICY_FILE" ] && [ ! -f "$POLICY_FILE" ]; then
  echo "Policy file not found: $POLICY_FILE" >&2
  exit 1
fi

api() {
  local method=$1 path=$2 data=${3:-}
  if [ -n "$data" ]; then
    curl -sS --fail -X "$method" -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \
      --data "$data" "$VAULT_ADDR$path"
  else
    curl -sS --fail -X "$method" -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR$path"
  fi
}

echo "[info] Ensuring AppRole auth backend enabled"
set +e
api GET /v1/sys/auth/approle | jq -e . >/dev/null 2>&1
rc=$?
set -e
if [ $rc -ne 0 ]; then
  echo "[info] enabling approle auth"
  api POST /v1/sys/auth/approle -s >/dev/null || true
fi

if [ -n "$POLICY_FILE" ]; then
  echo "[info] Uploading policy $POLICY_NAME from $POLICY_FILE"
  policy_body=$(jq -Rs --arg p "$(cat "$POLICY_FILE")" '{policy:$p}')
  api PUT /v1/sys/policy/$POLICY_NAME "$policy_body" >/dev/null
fi

echo "[info] Creating role $ROLE_NAME"
role_body='{"token_policies": ["'$POLICY_NAME'"], "token_ttl": "1h", "token_max_ttl": "4h"}'
api POST /v1/auth/approle/role/$ROLE_NAME "$role_body" >/dev/null || true

echo "[info] Fetching role_id"
role_id=$(api GET /v1/auth/approle/role/$ROLE_NAME/role-id | jq -r .data.role_id)

echo "[info] Creating secret_id"
secret_json=$(api POST /v1/auth/approle/role/$ROLE_NAME/secret-id | jq -r '.')
secret_id=$(echo "$secret_json" | jq -r '.data.secret_id')

echo "[info] Provisioned AppRole: role_id=$role_id secret_id=<redacted>"

if command -v gh >/dev/null 2>&1 && [ -n "$GIT_REPO" ]; then
  echo "[info] Creating repository secrets in $GIT_REPO via gh"
  echo "$role_id" | gh secret set VAULT_ROLE_ID --repo "$GIT_REPO" -y >/dev/null
  echo "$secret_id" | gh secret set VAULT_SECRET_ID --repo "$GIT_REPO" -y >/dev/null
  echo "[info] Set VAULT_ROLE_ID and VAULT_SECRET_ID in repo $GIT_REPO"
else
  echo "[info] gh CLI not available or GITHUB_REPOSITORY not set. Skipping repo secret creation."
  echo "role_id: $role_id"
  echo "secret_id: $secret_id"
fi

cat <<EOF
Provisioning complete.
If you set repository secrets with `gh`, workflows can use `secrets.VAULT_ROLE_ID` and `secrets.VAULT_SECRET_ID`.
Otherwise, provide these values to the workflow run environment or run the helper manually.
EOF

exit 0
