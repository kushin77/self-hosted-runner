#!/usr/bin/env bash
set -euo pipefail

# runner-watchdog.sh
# Checks GitHub runner status via gh API and restarts the docker-compose
# runner if it's offline. Intended to be run from the control host (workstation)
# or as a small cron/systemd-timer on the fullstack node.

REPO="kushin77/ElevatedIQ-Mono-Repo"
COMPOSE_DIR="/home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner"
CONTAINER_NAME="elevatediq-github-runner"
RUNNER_LABELS="self-hosted"

usage(){
  echo "Usage: $0 [--runner-name NAME] [--check-only] [--notify-test]"
  exit 1
}

RUNNER_NAME=""
CHECK_ONLY=0
NOTIFY_TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner-name) RUNNER_NAME="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift 1 ;;
    --notify-test) NOTIFY_TEST=1; shift 1 ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

# Optional notifier
NOTIFY_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify.sh"
if [[ -x "$NOTIFY_BIN" ]]; then
  source "$NOTIFY_BIN" || true
fi

if [[ "$NOTIFY_TEST" -eq 1 ]]; then
  if declare -f send_alert >/dev/null 2>&1; then
    send_alert "[test] Watchdog notification" "This is a test notification from runner-watchdog"
    echo "[watchdog] Sent test notification via notify.sh"
    exit 0
  else
    echo "[watchdog] notify.sh not available or send_alert not defined" >&2
    exit 2
  fi
fi

if [[ -z "$RUNNER_NAME" ]]; then
  # pick likely name (deployed default)
  RUNNER_NAME="elevatediq-runner-42"
fi

echo "[watchdog] Checking runner: $RUNNER_NAME in $REPO"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Exiting." >&2
  exit 2
fi

STATUS=$(gh api repos/${REPO}/actions/runners --jq ".runners[] | select(.name==\"${RUNNER_NAME}\") | .status" 2>/dev/null || true)

if [[ -z "$STATUS" ]]; then
  echo "[watchdog] Runner $RUNNER_NAME not found in repo (no entry)." >&2
  FOUND=0
else
  FOUND=1
fi

echo "[watchdog] Status: ${STATUS:-unknown}"

if [[ "$FOUND" -eq 1 && "$STATUS" == "online" ]]; then
  echo "[watchdog] Runner is online. Nothing to do."
  exit 0
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "[watchdog] Check-only mode; would restart when offline.";
  exit 0
fi

echo "[watchdog] Runner offline or missing; attempting restart of container on remote host"

ssh -o BatchMode=yes -o ConnectTimeout=10 akushnir@192.168.168.42 "set -euo pipefail; cd ${COMPOSE_DIR}; docker-compose pull || true; docker-compose restart ${CONTAINER_NAME} || docker-compose up -d ${CONTAINER_NAME}"

echo "[watchdog] Wait 15s and re-check"
sleep 15
NEW_STATUS=$(gh api repos/${REPO}/actions/runners --jq ".runners[] | select(.name==\"${RUNNER_NAME}\") | .status" 2>/dev/null || true)
echo "[watchdog] New status: ${NEW_STATUS:-unknown}"

if [[ "$NEW_STATUS" == "online" ]]; then
  echo "[watchdog] Restart succeeded"
  exit 0
else
  echo "[watchdog] Restart may have failed; check logs: ssh akushnir@192.168.168.42 'docker logs --tail 200 ${CONTAINER_NAME}'" >&2
  # Notify on repeated failure if notifier available
  if declare -f send_alert >/dev/null 2>&1; then
    send_alert "Runner watchdog: restart failed" "Attempted restart for ${RUNNER_NAME} on 192.168.168.42 but runner remains offline. See docker logs on host for details."
  fi
  exit 3
fi
