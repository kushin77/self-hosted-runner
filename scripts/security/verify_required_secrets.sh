#!/usr/bin/env bash
set -euo pipefail

REQUIRED=(
  "VAULT_ADDR"
  "VAULT_BOOTSTRAP_TOKEN"
  "VAULT_ROLE_ID"
  "MINIO_ROOT_USER"
  "MINIO_ROOT_PASSWORD"
  "MINIO_ENDPOINT"
)

MISSING=()

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not installed. Install from https://github.com/cli/cli and authenticate."
  exit 2
fi

for s in "${REQUIRED[@]}"; do
  if ! gh secret list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --limit 100 | awk '{print $1}' | grep -qx "$s"; then
    MISSING+=("$s")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "All required secrets are present"
  exit 0
else
  echo "Missing secrets: ${MISSING[*]}"
  exit 1
fi
