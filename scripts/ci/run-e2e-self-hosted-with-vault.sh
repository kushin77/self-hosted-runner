#!/usr/bin/env bash
set -euo pipefail

# Run end-to-end CI checks using Vault AppRole credentials available on the
# self-hosted runner host. This script is safe to run once the operator has
# provisioned `VAULT_ADDR` and either `VAULT_ROLE_ID`+`VAULT_SECRET_ID` or
# `VAULT_SECRET_ID_PATH` (a file containing the secret_id).

usage(){
  cat <<EOF
Usage: $0 [-t] [-p VAULT_SECRET_PATH]

Environment expectations:
  - VAULT_ADDR must be set
  - Either VAULT_ROLE_ID and VAULT_SECRET_ID OR VAULT_SECRET_ID_PATH must be set
  - Optional: GITHUB_TOKEN + gh CLI to trigger repository workflows

Options:
  -t    Run in "trigger workflow" mode: attempt to trigger GitHub workflow via gh
  -p    Path to Vault secret file (alternative to VAULT_SECRET_ID_PATH env)
EOF
}

TRIGGER_WORKFLOW=0
SECRET_PATH=""
while getopts ":tp:" opt; do
  case ${opt} in
    t) TRIGGER_WORKFLOW=1 ;;
    p) SECRET_PATH="$OPTARG" ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "ERROR: VAULT_ADDR is not set. Ask ops to provision Vault AppRole details." >&2
  exit 2
fi

if [ -z "${VAULT_ROLE_ID:-}" ] && [ -z "${VAULT_ROLE_ID_PLACEHOLDER:-}" ]; then
  echo "INFO: VAULT_ROLE_ID not set in environment; attempting to continue if workflow secrets available." >&2
fi

if [ -n "$SECRET_PATH" ]; then
  export VAULT_SECRET_ID_PATH="$SECRET_PATH"
fi

if [ -z "${VAULT_SECRET_ID:-}" ] && [ -n "${VAULT_SECRET_ID_PATH:-}" ]; then
  if [ -f "$VAULT_SECRET_ID_PATH" ]; then
    export VAULT_SECRET_ID="$(cat "$VAULT_SECRET_ID_PATH")"
  else
    echo "ERROR: VAULT_SECRET_ID_PATH is set but file does not exist: $VAULT_SECRET_ID_PATH" >&2
    exit 3
  fi
fi

echo "[e2e] VAULT_ADDR=${VAULT_ADDR}"
echo "[e2e] VAULT_ROLE_ID=${VAULT_ROLE_ID:-<not-set>}"
echo "[e2e] VAULT_SECRET_ID=${VAULT_SECRET_ID:-<not-set-or-file>}"

# Run the local test harness first
if [ -x ./scripts/automation/pmo/tests/test_runner_suite.sh ]; then
  echo "[e2e] Running local test harness..."
  ./scripts/automation/pmo/tests/test_runner_suite.sh
else
  echo "[e2e] Test harness not found or not executable; skipping local test run." >&2
fi

if [ "$TRIGGER_WORKFLOW" -eq 1 ]; then
  if command -v gh >/dev/null 2>&1 && [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "[e2e] Triggering GitHub Actions workflow 'deploy-immutable-ephemeral.yml'..."
    gh workflow run deploy-immutable-ephemeral.yml --field vault_secret_path="${VAULT_SECRET_PATH:-}" || true
    echo "[e2e] Workflow trigger attempted. Check workflow runs in GitHub UI." 
  else
    echo "[e2e] Cannot trigger workflow: 'gh' CLI or GITHUB_TOKEN missing." >&2
  fi
fi

echo "[e2e] Completed. If you provided temporary secrets, rotate or remove them after verification." 
