#!/usr/bin/env bash
set -euo pipefail
# rotate-runner.sh: gracefully rotate a self-hosted runner using a Vault-stored registration token.
# Usage: rotate-runner.sh <runner-dir> <repo-url> <runner-name> <vault-secret-path>
# Example: ./rotate-runner.sh /opt/actions-runner https://github.com/owner/repo my-runner secret/data/ci/self-hosted/my-runner

RUNNER_DIR=${1:-}
REPO_URL=${2:-}
RUNNER_NAME=${3:-}
SECRET_PATH=${4:-}
DRY=${DRY:-}

if [ -z "$RUNNER_DIR" ] || [ -z "$REPO_URL" ] || [ -z "$RUNNER_NAME" ] || [ -z "$SECRET_PATH" ]; then
  echo "Usage: $0 <runner-dir> <repo-url> <runner-name> <vault-secret-path>" >&2
  exit 2
fi

echo "Rotating runner in $RUNNER_DIR (name: $RUNNER_NAME) using secret $SECRET_PATH"

# Fetch a fresh registration token
REG_TOKEN=$(scripts/ci/get-runner-token.sh "$SECRET_PATH" --vault-addr "${VAULT_ADDR:-}")

if [ -z "$REG_TOKEN" ]; then
  echo "Failed to retrieve registration token" >&2
  exit 1
fi

cd "$RUNNER_DIR"

echo "Stopping service if installed"
if [ -x ./svc.sh ]; then
  sudo ./svc.sh stop || true
fi

if [ "${DRY:-}" = "1" ]; then
  echo "Dry run: would remove and reconfigure runner with token: (hidden)"
  exit 0
fi

# Try to remove old registration (best-effort)
if [ -x ./config.sh ]; then
  ./config.sh remove --token "$REG_TOKEN" || true
fi

# Reconfigure with fresh token
if [ -x ./config.sh ]; then
  ./config.sh --unattended --url "$REPO_URL" --token "$REG_TOKEN" --name "$RUNNER_NAME"
else
  echo "config.sh not present in $RUNNER_DIR" >&2
  exit 1
fi

# Reinstall service
if [ -x ./svc.sh ]; then
  sudo ./svc.sh install || true
  sudo ./svc.sh start || true
fi

echo "Rotation complete for $RUNNER_NAME"
