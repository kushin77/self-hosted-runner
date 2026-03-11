#!/usr/bin/env bash
# Run Phase 6 quickstart on a remote fullstack host via SSH
# Usage: FULLSTACK_USER=user FULLSTACK_HOST=host.example.com ./scripts/phase6-remote-runner.sh

set -euo pipefail

: ${FULLSTACK_USER:?Need FULLSTACK_USER}
: ${FULLSTACK_HOST:?Need FULLSTACK_HOST}
: ${REMOTE_REPO_PATH:="/home/${FULLSTACK_USER}/self-hosted-runner"}
: ${SSH_OPTS:="-o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new"}

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%SZ")
LOG_REMOTE="/tmp/phase6-quickstart-${TIMESTAMP}.log"
LOG_LOCAL="logs/phase6-remote-run-${TIMESTAMP}.log"
mkdir -p logs

echo "== Phase 6 remote runner =="
echo "Host: ${FULLSTACK_USER}@${FULLSTACK_HOST}"

# Pull latest changes on remote
ssh ${SSH_OPTS} "${FULLSTACK_USER}@${FULLSTACK_HOST}" \
  "set -euo pipefail; cd ${REMOTE_REPO_PATH} || exit 2; git fetch --all; git reset --hard origin/main"

# Run quickstart on remote and capture remote log
ssh ${SSH_OPTS} "${FULLSTACK_USER}@${FULLSTACK_HOST}" \
  "set -euo pipefail; cd ${REMOTE_REPO_PATH}; bash scripts/phase6-quickstart.sh 2>&1 | tee ${LOG_REMOTE}; exit \\${PIPESTATUS[0]}"

# Fetch remote logs/artifacts back to local logs/
scp ${SSH_OPTS} "${FULLSTACK_USER}@${FULLSTACK_HOST}:${LOG_REMOTE}" "${LOG_LOCAL}" || true

echo "Remote quickstart finished. Remote log saved to ${LOG_LOCAL}"

echo "You can inspect the log with: tail -n 200 ${LOG_LOCAL}"

exit 0
