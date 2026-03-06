#!/usr/bin/env bash
set -euo pipefail
# vault_oidc_auth.sh: obtain a Vault client token using an OIDC JWT (prototype)
# Usage:
#  VAULT_ADDR=https://vault.example.com VAULT_OIDC_JWT=... ./vault_oidc_auth.sh --role my-role

ROLE=""
VAULT_ADDR=${VAULT_ADDR:-}
VAULT_OIDC_JWT=${VAULT_OIDC_JWT:-}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --vault-addr) VAULT_ADDR="$2"; shift 2 ;;
    --jwt) VAULT_OIDC_JWT="$2"; shift 2 ;;
    --help) echo "Usage: $0 --role ROLE [--vault-addr URL] [--jwt JWT]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROLE" ]; then
  echo "--role is required" >&2
  exit 2
fi

if [ -z "$VAULT_ADDR" ]; then
  echo "VAULT_ADDR must be set via env or --vault-addr" >&2
  exit 2
fi

# If VAULT_TOKEN already present, return it
if [ -n "${VAULT_TOKEN:-}" ]; then
  echo "$VAULT_TOKEN"
  exit 0
fi

# Require a JWT (caller should fetch from cloud metadata, GitHub OIDC, or other identity provider)
if [ -z "$VAULT_OIDC_JWT" ]; then
  echo "VAULT_OIDC_JWT not provided. Provide a JWT via env VAULT_OIDC_JWT or --jwt." >&2
  exit 2
fi

# Try login via the default OIDC mount at auth/oidc/login (adjust if your Vault mount differs)
LOGIN_PATH="/v1/auth/oidc/login"

for i in 1 2 3; do
  set +e
  RESP=$(curl -sSf --max-time 10 --header "Content-Type: application/json" \
    --data "{\"role\": \"${ROLE}\", \"jwt\": \"${VAULT_OIDC_JWT}\"}" \
    "$VAULT_ADDR$LOGIN_PATH" 2>/dev/null)
  rc=$?
  set -e
  if [ $rc -eq 0 ] && [ -n "$RESP" ]; then
    break
  fi
  sleep $((i*2))
done

if [ -z "${RESP:-}" ]; then
  echo "Failed to contact Vault at $VAULT_ADDR$LOGIN_PATH" >&2
  exit 1
fi

# Extract client token
if command -v jq >/dev/null 2>&1; then
  TOKEN=$(echo "$RESP" | jq -r '.auth.client_token // empty')
else
  TOKEN=$(echo "$RESP" | python3 - <<'PY'
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('auth',{}).get('client_token',''))
except Exception:
    print('')
PY
)
fi

if [ -z "$TOKEN" ]; then
  echo "Failed to extract Vault client token from response" >&2
  exit 1
fi

# Output token only
printf '%s' "$TOKEN"
