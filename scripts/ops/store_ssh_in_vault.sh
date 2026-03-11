#!/usr/bin/env bash
set -euo pipefail
# Store an SSH private key into HashiCorp Vault KV (v2) idempotently
# Usage: store_ssh_in_vault.sh --mount-path secret --path verifier/ssh_key --file /path/to/key

usage(){
  cat <<EOF
Usage: $0 --mount-path MOUNT --path SECRET_PATH --file /path/to/private_key

Example:
  $0 --mount-path secret --path verifier/ssh_key --file /tmp/verifier_key
EOF
  exit 1
}

MOUNT="secret"
PATH_KEY=""
KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mount-path) MOUNT="$2"; shift 2;;
    --path) PATH_KEY="$2"; shift 2;;
    --file) KEY_FILE="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$PATH_KEY" || -z "$KEY_FILE" ]]; then
  usage
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Key file not found: $KEY_FILE" >&2
  exit 2
fi

DATA=$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$KEY_FILE")

# Write to Vault KV v2
vault kv put "$MOUNT/$PATH_KEY" private_key="$DATA"

echo "Stored SSH key in Vault at ${MOUNT}/${PATH_KEY}"
exit 0
