#!/usr/bin/env bash
set -euo pipefail
# Store a token/value into HashiCorp Vault KV (v2)
# Usage: store_token_in_vault.sh --mount-path secret --path verifier/github_token --value "token"

usage(){
  cat <<EOF
Usage: $0 --mount-path MOUNT --path SECRET_PATH --value TOKEN

Example:
  $0 --mount-path secret --path verifier/github_token --value "ghp_..."
EOF
  exit 1
}

MOUNT="secret"
PATH_KEY=""
VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mount-path) MOUNT="$2"; shift 2;;
    --path) PATH_KEY="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$PATH_KEY" || -z "$VALUE" ]]; then
  usage
fi

vault kv put "$MOUNT/$PATH_KEY" value="$VALUE"
echo "Stored token in Vault at ${MOUNT}/${PATH_KEY}"
exit 0
