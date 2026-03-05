#!/usr/bin/env bash
set -euo pipefail

# Lightweight auto-heal for self-hosted runner service.
# NOTE: This script assumes systemd and a service named 'actions.runner.*.service' or 'actions.runner.service'.

SERVICE_NAME=${1:-actions.runner}

echo "Running diagnostics and attempting restart for ${SERVICE_NAME}"
./scripts/runner/runner-diagnostics.sh || true

if command -v systemctl >/dev/null 2>&1; then
  echo "Restarting ${SERVICE_NAME} via systemctl"
  sudo systemctl restart "${SERVICE_NAME}" || sudo systemctl restart actions.runner || true
  sudo systemctl status "${SERVICE_NAME}" --no-pager || true
else
  echo "systemctl not available; please restart runner manually"
fi
