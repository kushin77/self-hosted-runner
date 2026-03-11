#!/bin/bash
#
# deploy-watch-automation.sh - Deploy watching automation as background job
# Sets up continuous operator provision monitoring (immutable, ephemeral, hands-off)
#
# Execution: bash scripts/automation/deploy-watch-automation.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Configuration
LOG_DIR="${PROJECT_ROOT}/logs/automation"
WATCH_SCRIPT="${SCRIPT_DIR}/automation/watch-operator-provision.sh"
WATCH_PID_FILE="${LOG_DIR}/.watch_operator_provision.pid"
ON_PREM_HOST="${ONPREM_HOST:-192.168.168.42}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_msg() {
  echo -e "${GREEN}[✓]${NC} $1"
}

warn_msg() {
  echo -e "${YELLOW}[!]${NC} $1"
}

err_msg() {
  echo -e "${RED}[✗]${NC} $1"
}

# Ensure directories exist
mkdir -p "${LOG_DIR}"

# Make watch script executable
chmod +x "${WATCH_SCRIPT}"

log_msg "Deploying operator provision watcher automation"

# Check if already running
if [ -f "${WATCH_PID_FILE}" ]; then
  OLD_PID=$(cat "${WATCH_PID_FILE}")
  if kill -0 "${OLD_PID}" 2>/dev/null; then
    warn_msg "Watcher already running (PID: ${OLD_PID})"
    exit 0
  else
    log_msg "Removing stale PID file"
    rm -f "${WATCH_PID_FILE}"
  fi
fi

# Start watcher in background
log_msg "Starting operator provision watcher in background"
log_msg "Configuration:"
log_msg "  - Watch interval: 60 seconds"
log_msg "  - Max duration: 24 hours"
log_msg "  - Target host: ${ON_PREM_HOST}:8000"
log_msg "  - Log location: ${LOG_DIR}/watch-operator-provision-*.jsonl"

# Start background process
nohup bash "${WATCH_SCRIPT}" 60 \
  > "${LOG_DIR}/watch-operator-provision.out" \
  2> "${LOG_DIR}/watch-operator-provision.err" &

WATCH_PID=$!
echo "${WATCH_PID}" > "${WATCH_PID_FILE}"

log_msg "Watcher started (PID: ${WATCH_PID})"
log_msg "Status:"
log_msg "  - Process ID: ${WATCH_PID}"
log_msg "  - Output log: ${LOG_DIR}/watch-operator-provision.out"
log_msg "  - Error log: ${LOG_DIR}/watch-operator-provision.err"
log_msg "  - Event logs: ${LOG_DIR}/watch-operator-provision-*.jsonl (append-only)"

echo ""
log_msg "Automation deployed successfully!"
log_msg "Watcher will automatically:"
log_msg "  1. Check every 60 seconds for SSH key in GSM or sudo access"
log_msg "  2. Trigger comprehensive re-validation when detected"
log_msg "  3. Post evidence to GitHub issue #2594"
log_msg "  4. Close blocking issue #2608"
log_msg "  5. Mark deployment as fully verified"

echo ""
warn_msg "Monitor with: tail -f ${LOG_DIR}/watch-operator-provision.out"
warn_msg "Kill with: kill ${WATCH_PID}"
