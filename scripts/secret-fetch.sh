#!/usr/bin/env bash
set -euo pipefail

# secret-fetch.sh
# Usage: secret-fetch.sh <SECRET_NAME>
# Tries in order: environment variable, Google Secret Manager, Vault

NAME="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

print_and_exit() {
  echo "$1"
  exit 0
}

# 1) Env var
if [ -n "${!NAME-}" ]; then
  print_and_exit "${!NAME}"
fi

# 2) Google Secret Manager (requires gcloud authenticated and GCP_PROJECT env)
if command -v gcloud >/dev/null 2>&1 && [ -n "${GCP_PROJECT_ID-}" ]; then
  if gcloud secrets versions access latest --secret="$NAME" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets versions access latest --secret="$NAME" --project="$GCP_PROJECT_ID" || true
    exit 0
  fi
fi

# 3) Vault (requires VAULT_ADDR and VAULT_TOKEN)
if command -v vault >/dev/null 2>&1 && [ -n "${VAULT_ADDR-}" ] && [ -n "${VAULT_TOKEN-}" ]; then
  if vault kv get -field=value secret/runner/"$NAME" >/dev/null 2>&1; then
    vault kv get -field=value secret/runner/"$NAME" || true
    exit 0
  fi
fi

echo ""
exit 1
