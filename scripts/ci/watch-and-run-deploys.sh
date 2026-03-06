#!/usr/bin/env bash
set -euo pipefail

# Watch for Vault repo secrets and dispatch deploy workflows when present.
# Requires: `gh` CLI authenticated with repo write access.
# Usage: GH_REPO=kushin77/self-hosted-runner ./scripts/ci/watch-and-run-deploys.sh

GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-${GH_REPO:-kushin77/self-hosted-runner}}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}    # seconds
MAX_CHECKS=${MAX_CHECKS:-360}          # default ~6 hours

echo "[info] Watching repo $GITHUB_REPOSITORY for Vault secrets (VAULT_ROLE_ID or VAULT_ADMIN_TOKEN)..."
count=0
while [ $count -lt "$MAX_CHECKS" ]; do
  count=$((count+1))
  if gh secret list --repo "$GITHUB_REPOSITORY" 2>/dev/null | grep -q -E "VAULT_ROLE_ID|VAULT_ADMIN_TOKEN"; then
    echo "[info] Required secret detected. Dispatching deploy workflows..."
    gh workflow run .github/workflows/deploy-immutable-ephemeral.yml --ref main || true
    gh workflow run .github/workflows/deploy-rotation-staging.yml --ref main || true
    echo "[info] Dispatched workflows. Exiting watcher."
    exit 0
  fi
  echo "[debug] check #$count: secrets not found; sleeping ${CHECK_INTERVAL}s"
  sleep "$CHECK_INTERVAL"
done

echo "[error] Timed out waiting for secrets after $((CHECK_INTERVAL*MAX_CHECKS)) seconds"
exit 2
