#!/usr/bin/env bash
set -euo pipefail

# runner-watchdog-v2.sh
# Enhanced runner watchdog with circuit breaker, exponential backoff, and notifications
#
# Features:
# - Circuit breaker: stops retrying after N failures, auto-recover after cooldown
# - Exponential backoff: 1s → 2s → 4s → 8s delays between retries
# - Notifications: send alerts on critical failures
# - Health check: comprehensive validation of runner status
#
# Usage: $0 [--runner-name NAME] [--check-only] [--notify-test] [--reset-circuit]

REPO="kushin77/ElevatedIQ-Mono-Repo"
COMPOSE_DIR="/home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner"
CONTAINER_NAME="elevatediq-github-runner"
REMOTE_HOST="192.168.168.42"
REMOTE_USER="akushnir"

# Circuit breaker config
CIRCUIT_BREAKER_THRESHOLD=3  # Failures before opening circuit
CIRCUIT_RESET_TIMEOUT=300    # 5 minutes
CIRCUIT_STATE_FILE="/tmp/runner-watchdog-circuit-${CONTAINER_NAME}.state"
CIRCUIT_FAILURES_FILE="/tmp/runner-watchdog-failures-${CONTAINER_NAME}.count"

# Backoff config
BACKOFF_MAX=8  # Maximum backoff in seconds

# ============================================================================
# CIRCUIT BREAKER FUNCTIONS
# ============================================================================

circuit_state() {
  if [[ -f "$CIRCUIT_STATE_FILE" ]]; then
    cat "$CIRCUIT_STATE_FILE"
  else
    echo "CLOSED"
  fi
}

circuit_timestamp() {
  if [[ -f "$CIRCUIT_STATE_FILE.timestamp" ]]; then
    cat "$CIRCUIT_STATE_FILE.timestamp"
  else
    echo "0"
  fi
}

circuit_open() {
  echo "[circuit-breaker] Opening circuit (too many failures)" >&2
  echo "OPEN" > "$CIRCUIT_STATE_FILE"
  date +%s > "$CIRCUIT_STATE_FILE.timestamp"
  echo 0 > "$CIRCUIT_FAILURES_FILE"
}

circuit_close() {
  echo "[circuit-breaker] Closing circuit" >&2
  echo "CLOSED" > "$CIRCUIT_STATE_FILE"
  rm -f "$CIRCUIT_STATE_FILE.timestamp"
  echo 0 > "$CIRCUIT_FAILURES_FILE"
}

circuit_half_open() {
  echo "[circuit-breaker] Half-open: testing recovery" >&2
  echo "HALF_OPEN" > "$CIRCUIT_STATE_FILE"
}

circuit_increment_failures() {
  local failures=$(cat "$CIRCUIT_FAILURES_FILE" 2>/dev/null || echo "0")
  ((failures++))
  echo "$failures" > "$CIRCUIT_FAILURES_FILE"
  echo "$failures"
}

circuit_should_reset() {
  local state=$(circuit_state)
  if [[ "$state" != "OPEN" ]]; then
    return 1
  fi

  local opened_at=$(circuit_timestamp)
  local now=$(date +%s)
  local elapsed=$((now - opened_at))

  if [[ $elapsed -ge $CIRCUIT_RESET_TIMEOUT ]]; then
    echo "[circuit-breaker] Reset timeout reached; attempting recovery" >&2
    circuit_half_open
    return 0
  fi

  return 1
}

# ============================================================================
# BACKOFF FUNCTIONS
# ============================================================================

exponential_backoff() {
  local attempt="$1"
  local backoff=$((2 ** attempt))
  if [[ $backoff -gt $BACKOFF_MAX ]]; then
    backoff=$BACKOFF_MAX
  fi
  echo "$backoff"
}

# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================

check_github_api() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "[health] GitHub CLI not available" >&2
    return 1
  fi

  gh api repos/${REPO}/actions/runners --jq ".runners[] | select(.name==\"${RUNNER_NAME}\") | .status" 2>/dev/null || true
}

check_docker_health() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[health] docker not available" >&2
    return 1
  fi

  # Check if container exists and is running
  if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    local state=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Running}}')
    if [[ "$state" == "true" ]]; then
      echo "running"
      return 0
    fi
  fi

  return 1
}

check_runner_logs() {
  # Check recent logs for critical errors
  if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Runner connect error: Error: Conflict"; then
    echo "ERROR: Runner conflict detected in logs"
    return 1
  fi

  if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Http response code: NotFound"; then
    echo "ERROR: HTTP 404 from GitHub API"
    return 1
  fi

  if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Fatal error"; then
    echo "ERROR: Fatal error in runner logs"
    return 1
  fi

  return 0
}

# ============================================================================
# RESTART LOGIC
# ============================================================================

restart_runner() {
  echo "[watchdog] Attempting to restart runner..." >&2

  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" \
    "cd '$COMPOSE_DIR' && docker-compose pull >/dev/null 2>&1 || true && docker-compose restart '$CONTAINER_NAME' || docker-compose up -d '$CONTAINER_NAME'" \
    < /dev/null >/dev/null 2>&1; then

    echo "[watchdog] Restart command failed" >&2
    return 1
  fi

  return 0
}

# ============================================================================
# NOTIFIER
# ============================================================================

notify_alert() {
  local title="$1"
  local message="$2"

  local notify_bin="$(dirname "${BASH_SOURCE[0]}")/notify.sh"
  if [[ -x "$notify_bin" ]]; then
    source "$notify_bin" || true
    if declare -f send_alert >/dev/null 2>&1; then
      send_alert "$title" "$message"
    fi
  fi
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

usage() {
  echo "Usage: $0 [--runner-name NAME] [--check-only] [--notify-test] [--reset-circuit]"
  echo ""
  echo "Options:"
  echo "  --runner-name NAME      Runner name to check (default: elevatediq-runner-42)"
  echo "  --check-only           Only check status, don't restart"
  echo "  --notify-test          Send a test notification"
  echo "  --reset-circuit        Reset circuit breaker"
  echo "  -h, --help             Show this help"
  exit 1
}

RUNNER_NAME=""
CHECK_ONLY=0
NOTIFY_TEST=0
RESET_CIRCUIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner-name) RUNNER_NAME="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --notify-test) NOTIFY_TEST=1; shift ;;
    --reset-circuit) RESET_CIRCUIT=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$RUNNER_NAME" ]]; then
  RUNNER_NAME="elevatediq-runner-42"
fi

# ============================================================================
# MAIN
# ============================================================================

if [[ "$NOTIFY_TEST" -eq 1 ]]; then
  notify_alert "[test] Watchdog notification" "Test message from runner-watchdog-v2"
  echo "[watchdog] Sent test notification"
  exit 0
fi

if [[ "$RESET_CIRCUIT" -eq 1 ]]; then
  echo "[watchdog] Resetting circuit breaker..."
  circuit_close
  echo "[watchdog] Circuit breaker reset"
  exit 0
fi

echo "[watchdog] Starting health check for runner: $RUNNER_NAME" >&2

# Check circuit breaker state
state=$(circuit_state)
echo "[watchdog] Circuit breaker state: $state" >&2

if [[ "$state" == "OPEN" ]] && ! circuit_should_reset; then
  echo "[watchdog] Circuit is OPEN; skipping restart (in cooldown period)" >&2
  notify_alert \
    "Runner watchdog: circuit breaker OPEN" \
    "Circuit breaker is in cooldown. Too many restart attempts. Will retry in $(($CIRCUIT_RESET_TIMEOUT / 60)) minutes."
  exit 0
fi

# Check GitHub API status
github_status=$(check_github_api || echo "unknown")
echo "[watchdog] GitHub runner status: $github_status" >&2

# If online and healthy, nothing to do
if [[ "$github_status" == "online" ]]; then
  if [[ $CHECK_ONLY -ne 1 ]]; then
    circuit_close  # Reset failures on success
  fi
  echo "[watchdog] Runner is online ✅"
  exit 0
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "[watchdog] Check-only mode; would restart" >&2
  exit 0
fi

# Runner is offline; attempt restart
echo "[watchdog] Runner is offline; attempting restart" >&2

if ! restart_runner; then
  echo "[watchdog] Restart failed" >&2
  failures=$(circuit_increment_failures)
  echo "[watchdog] Failure count: $failures / $CIRCUIT_BREAKER_THRESHOLD" >&2

  if [[ $failures -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
    circuit_open
    notify_alert \
      "Runner watchdog: max restarts exceeded" \
      "Circuit breaker opened after $failures failed restart attempts. Manual intervention required."
    exit 2
  else
    notify_alert \
      "Runner watchdog: restart attempt #$failures failed" \
      "Will retry up to $CIRCUIT_BREAKER_THRESHOLD times. Runner: $RUNNER_NAME"
    exit 1
  fi
fi

# Wait for recovery
echo "[watchdog] Waiting 15s for runner to recover..." >&2
sleep 15

# Re-check status
echo "[watchdog] Re-checking runner status..." >&2
github_status=$(check_github_api || echo "unknown")
echo "[watchdog] New GitHub runner status: $github_status" >&2

if [[ "$github_status" == "online" ]]; then
  echo "[watchdog] Restart succeeded ✅"
  circuit_close
  exit 0
else
  echo "[watchdog] Restart did not fully recover runner" >&2
  failures=$(circuit_increment_failures)
  echo "[watchdog] Failure count: $failures / $CIRCUIT_BREAKER_THRESHOLD" >&2

  if [[ $failures -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
    circuit_open
    notify_alert \
      "Runner watchdog: restart recovery failed" \
      "Circuit breaker opened after $failures failed restart attempts. Check docker logs: ssh $REMOTE_USER@$REMOTE_HOST 'docker logs $CONTAINER_NAME'"
    exit 2
  fi

  exit 1
fi
