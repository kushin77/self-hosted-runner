#!/usr/bin/env bash
set -euo pipefail

# bootstrap-secrets.sh
# Uses `provision-secrets.sh` to retrieve secrets from secret manager(s)
# and writes an atomic `.env` file on the remote host with strict permissions.
# This script contains no secret values and only documents the recommended flow.

OUT_ENV=${OUT_ENV:-.env}
TMP_ENV=/tmp/.env.$$

usage(){
  cat <<EOF
Usage: $0 --secret <name> --provider <vault|gsm|gcp-kms> [--key <env_key_name>]

Example:
  # Fetch DB DSN from Vault and write to .env as POSTGRES_DSN
  ./scripts/bootstrap-secrets.sh --secret nexusshield/postgres --provider vault --key POSTGRES_DSN

Notes:
  - This script expects `scripts/provision-secrets.sh` to be configured for your provider.
  - Secrets should never be echoed or stored in git.
  - After the .env is created, set strict permissions: chmod 600 .env
EOF
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

SECRET_NAME=""
PROVIDER=""
KEY_NAME=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --secret) SECRET_NAME="$2"; shift 2;;
    --provider) PROVIDER="$2"; shift 2;;
    --key) KEY_NAME="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg $1"; usage; exit 2;;
  esac
done

if [ -z "$SECRET_NAME" ] || [ -z "$PROVIDER" ] || [ -z "$KEY_NAME" ]; then
  usage
  exit 2
fi

# Example: provision-secrets.sh writes secret value to stdout or a temporary file.
# Here we call provision-secrets.sh and capture output to the tmp env file.

echo "# Generated .env (do not commit)" > "$TMP_ENV"
echo "# secret: $SECRET_NAME (provider: $PROVIDER)" >> "$TMP_ENV"

# Provision and capture secret value. The provision script is a placeholder and
# should be implemented to print the secret value to stdout when called with
# the appropriate args. Replace with your secret-manager implementation.

SECRET_VAL=$(scripts/provision-secrets.sh "$PROVIDER" --name "$SECRET_NAME" --value-from file:./secrets/placeholder 2>/dev/null || true)

if [ -z "$SECRET_VAL" ]; then
  echo "Failed to retrieve secret (placeholder) — replace provision-secrets.sh implementation or provide value file" >&2
  exit 3
fi

echo "$KEY_NAME=$SECRET_VAL" >> "$TMP_ENV"

# Atomically move into place with strict permissions
mv "$TMP_ENV" "$OUT_ENV"
chmod 600 "$OUT_ENV"
echo "Wrote secrets to $OUT_ENV (permissions 600)."
