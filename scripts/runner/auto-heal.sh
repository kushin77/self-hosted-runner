#!/usr/bin/env bash
set -euo pipefail

# Lightweight auto-heal for self-hosted runner service with ephemeral guarantees.
# NOTE: This script assumes systemd and a service named 'actions.runner.*.service' or 'actions.runner.service'.
# EPHEMERAL: Cleans runner state before restart to ensure reproducible, immutable behavior.

SERVICE_NAME=${1:-actions.runner}

log_info() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [auto-heal] $*"
}

log_info "=== Auto-Heal START for ${SERVICE_NAME} ==="
log_info "Running diagnostics"
./scripts/runner/runner-diagnostics.sh || true

# Ephemeral cleanup: wipe state before restart
if [ -f ./scripts/runner/runner-ephemeral-cleanup.sh ]; then
  log_info "Enforcing ephemeral state (clean restart)"
  chmod +x ./scripts/runner/runner-ephemeral-cleanup.sh
  ./scripts/runner/runner-ephemeral-cleanup.sh || log_info "Ephemeral cleanup encountered issues but continuing"
else
  log_info "Warning: ephemeral cleanup script not found; skipping state wipe"
fi

if command -v systemctl >/dev/null 2>&1; then
  log_info "Restarting ${SERVICE_NAME} via systemctl (with clean state)"
  sudo systemctl restart "${SERVICE_NAME}" || sudo systemctl restart actions.runner || true
  sleep 2
  sudo systemctl status "${SERVICE_NAME}" --no-pager || true
  log_info "=== Auto-Heal COMPLETE ==="
else
  log_info "systemctl not available; please restart runner manually"
  log_info "=== Auto-Heal INCOMPLETE ==="
  exit 1
fi
