#!/usr/bin/env bash
set -euo pipefail
# get-runner-token.sh: retrieve GitHub runner registration token from Vault KV v2
# Usage: get-runner-token.sh <vault-secret-path> [--vault-addr URL]
# Example: ./get-runner-token.sh secret/data/ci/self-hosted/my-runner --vault-addr https://vault.example.com

SECRET_PATH=${1:-}
VAULT_ADDR=${VAULT_ADDR:-}

if [ -z "$SECRET_PATH" ]; then
  echo "Usage: $0 <vault-secret-path> [--vault-addr URL]" >&2
  exit 2
fi

# optional args
if [ "$2" = "--vault-addr" ]; then
  VAULT_ADDR="$3"
fi

# If VAULT_TOKEN env available, use it; otherwise call vault_oidc_auth.sh
if [ -n "${VAULT_TOKEN:-}" ]; then
  TOKEN="$VAULT_TOKEN"
else
  # Expect role and VAULT_OIDC_JWT to be set in env or rely on vault_oidc_auth.sh defaults
  TOKEN=$(scripts/ci/vault_oidc_auth.sh --role "${VAULT_OIDC_ROLE:-runner-role}" --vault-addr "${VAULT_ADDR}")
fi

if [ -z "$VAULT_ADDR" ]; then
  echo "VAULT_ADDR is required (env or --vault-addr)" >&2
  exit 2
fi

# Read secret (support KV v2 path shapes). Accept both `secret/data/...` and `secret/...` by attempting both shapes.
read_secret() {
  local path="$1"
  local resp
  set +e
  resp=$(curl -sSf --header "X-Vault-Token: $TOKEN" --max-time 10 "$VAULT_ADDR/v1/$path" 2>/dev/null)
  rc=$?
  set -e
  if [ $rc -ne 0 ] || [ -z "${resp}" ]; then
    echo ""
  else
    echo "$resp"
  fi
}

JSON=""
# try as-is
JSON=$(read_secret "$SECRET_PATH")
if [ -z "$JSON" ]; then
  # try KV v2 common layout: secret/data/<rest>
  JSON=$(read_secret "${SECRET_PATH#secret/}")
fi

if [ -z "$JSON" ]; then
  echo "Failed to read secret at $SECRET_PATH" >&2
  exit 1
fi

# extract token
if command -v jq >/dev/null 2>&1; then
  RUNNER_TOKEN=$(echo "$JSON" | jq -r '.data.data.token // .data.token // .token // empty')
else
  RUNNER_TOKEN=$(echo "$JSON" | python3 - <<'PY'
import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print('')
    sys.exit(0)
for key in (('data','data','token'), ('data','token'), ('token',)):
    cur=d
    ok=True
    for k in key:
        if isinstance(cur,dict) and k in cur:
            cur=cur[k]
        else:
            ok=False
            break
    if ok and cur:
        print(cur)
        sys.exit(0)
print('')
PY
)
fi

if [ -z "$RUNNER_TOKEN" ]; then
  echo "Runner token not found in secret at $SECRET_PATH" >&2
  exit 1
fi

# print token only
printf '%s' "$RUNNER_TOKEN"
