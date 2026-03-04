#!/usr/bin/env bash
set -euo pipefail

# run-safe.sh - Run a script or command non-interactively under nohup
# Writes stdout/stderr to a timestamped log in /tmp and returns immediately.
# Usage: run-safe.sh --label NAME -- cmd args...

LABEL="run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--label NAME] -- <command> [args...]" >&2
  exit 2
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOGFILE="/tmp/${LABEL}-${TIMESTAMP}.log"

echo "Starting command in background. Log: ${LOGFILE}"

# Run the command under setsid + nohup so it won't hold the SSH session.
setsid nohup "$@" >"${LOGFILE}" 2>&1 &
PID=$!

echo "PID: ${PID}"
echo "Log: ${LOGFILE}"
echo "Started: $(date -Iseconds)"

exit 0
