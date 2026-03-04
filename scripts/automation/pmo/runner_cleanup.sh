#!/usr/bin/env bash
set -euo pipefail
# Runner cleanup helper for self-hosted GitHub Actions runners
# Usage:
#   sudo ./scripts/pmo/runner_cleanup.sh [--dry-run]

DRY_RUN=0
if [ "${1-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

WORKER_ROOT="/home/akushnir/actions-runner-org-42"
OUTFILE="/tmp/runner_cleanup_$(date +%s).log"

run() {
  echo "+ $*" | tee -a "$OUTFILE"
  if [ $DRY_RUN -eq 1 ]; then
    return 0
  fi
  eval "$@" 2>&1 | tee -a "$OUTFILE"
}

echo "Runner cleanup started: $(date)" | tee -a "$OUTFILE"

if [ ! -d "$WORKER_ROOT" ]; then
  echo "Worker root $WORKER_ROOT not found. Exiting." | tee -a "$OUTFILE"
  exit 1
fi

echo "[1/6] Stopping any runner services (best-effort)" | tee -a "$OUTFILE"
run "systemctl stop 'actions.runner.*' || true"

echo "[2/6] Ensure ownership for runner directories" | tee -a "$OUTFILE"
run "chown -R actions:actions '$WORKER_ROOT' || true"

echo "[3/6] Normalize directory and file permissions" | tee -a "$OUTFILE"
run "find '$WORKER_ROOT/_work' -type d -exec chmod 750 {} + || true"
run "find '$WORKER_ROOT/_work' -type f -exec chmod 640 {} + || true"

echo "[4/6] Audit existing .backups and node_modules (listing only)" | tee -a "$OUTFILE"
run "ls -ld '$WORKER_ROOT'/*/.backups 2>/dev/null || true"
run "ls -ld '$WORKER_ROOT'/*/apps/portal/node_modules 2>/dev/null || true"

echo "[5/6] Remove stale node_modules and .backups directories (dangerous - audited)" | tee -a "$OUTFILE"
run "rm -rf '$WORKER_ROOT'/*/apps/portal/node_modules || true"
run "rm -rf '$WORKER_ROOT'/*/.backups || true"

echo "[6/6] Test non-root write as 'actions' user" | tee -a "$OUTFILE"
run "sudo -u actions -- bash -c 'touch $WORKER_ROOT/_work/runner_cleanup_test 2>/dev/null && rm -f $WORKER_ROOT/_work/runner_cleanup_test || true'"

echo "Restarting runner services (best-effort)" | tee -a "$OUTFILE"
run "systemctl start 'actions.runner.*' || true"

echo "Runner cleanup finished: $(date)" | tee -a "$OUTFILE"
echo "Logs written to: $OUTFILE"

exit 0
