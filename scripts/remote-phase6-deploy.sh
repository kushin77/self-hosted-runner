#!/usr/bin/env bash
# Remote Phase 6 deploy helper
# Usage: ./scripts/remote-phase6-deploy.sh fullstack [--tail]
#
# This script SSHs to the target "fullstack" host, runs the Phase 6 quickstart,
# captures logs to the remote logs/ directory and runs the health-check.
# It intentionally contains NO secrets and follows the direct-deploy model.

set -euo pipefail
TARGET_HOST="${1:-fullstack}"
TAIL_LOG=false
if [[ "${2:-}" == "--tail" ]]; then
  TAIL_LOG=true
fi

REMOTE_REPO_DIR="/home/akushnir/self-hosted-runner"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
REMOTE_LOG="${REMOTE_REPO_DIR}/logs/phase6-deploy-${TIMESTAMP}.log"

echo "Running Phase 6 deploy on ${TARGET_HOST} (logs -> ${REMOTE_LOG})"

SSH_CMD=$(cat <<SSH_EOF
set -euo pipefail
cd /home/akushnir/self-hosted-runner
# load env from .env if present (no secrets printed)
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi
mkdir -p logs
# Run quickstart and capture output
bash scripts/phase6-quickstart.sh 2>&1 | tee "${REMOTE_LOG}"
# Run health checks
bash scripts/phase6-health-check.sh --full 2>&1 | tee -a "${REMOTE_LOG}"
SSH_EOF
)

# Execute remote commands
ssh -o StrictHostKeyChecking=accept-new "${TARGET_HOST}" "${SSH_CMD}"

if [ "$TAIL_LOG" = true ]; then
  echo "Tailing remote log (press Ctrl-C to exit)..."
  ssh "${TARGET_HOST}" "tail -f ${REMOTE_LOG}"
fi

echo "Remote Phase 6 deploy finished. Remote log: ${REMOTE_LOG}"