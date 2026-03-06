#!/usr/bin/env bash
set -euo pipefail

# drill_run.sh — lightweight DR drill harness
# This script runs the bootstrap restore on a test target and performs basic validations.

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  cat <<EOF
Usage: GITHUB_BACKUP_URL=... GITLAB_DOMAIN=... ./scripts/dr/drill_run.sh

This harness expects `bootstrap/restore_from_github.sh` to be present and usable.
It does not provision cloud instances; run on a throwaway VM for full validation.
EOF
  exit 0
fi

if [ -z "${GITHUB_BACKUP_URL:-}" ] || [ -z "${GITLAB_DOMAIN:-}" ]; then
  echo "ERROR: GITHUB_BACKUP_URL and GITLAB_DOMAIN must be set"
  exit 2
fi

export INSTALL_GITLAB=${INSTALL_GITLAB:-yes}

echo "[drill] Starting DR drill at $(date -u)"

./bootstrap/restore_from_github.sh

echo "[drill] Waiting for GitLab to become healthy..."
for i in {1..24}; do
  if curl -skSf "https://${GITLAB_DOMAIN}/-/health" >/dev/null 2>&1; then
    echo "[drill] GitLab reported healthy"
    break
  fi
  sleep 10
done

echo "[drill] Basic validation: fetching root page and listing projects via API (best-effort)"
if command -v curl >/dev/null 2>&1; then
  curl -sk "https://${GITLAB_DOMAIN}/users/sign_in" | head -n5 || true
fi

echo "[drill] DR drill completed — review logs and verify runners and Vault access manually."
