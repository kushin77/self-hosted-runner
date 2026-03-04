#!/usr/bin/env bash
# runner-audit.sh - Audit logging sidecar for GitHub Actions runner
# Logs all runner actions (start, stop, restart, errors) to structured JSON
#
# Usage: ./runner-audit.sh [--container-name NAME] [--log-file PATH]

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-elevatediq-github-runner}"
LOG_FILE="${LOG_FILE:-/var/log/runner-audit.log}"
DEBUG="${DEBUG:-0}"

# Create log directory if needed
LOG_DIR="$(dirname "$LOG_FILE")"
if [[ ! -d "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR" || {
    LOG_FILE="/tmp/runner-audit.log"
    LOG_DIR="/tmp"
  }
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_json() {
  local action="$1"
  local status="$2"
  local message="${3:-}"
  local user="${4:-$(whoami)}"

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local trace_id="$(uuidgen 2>/dev/null || echo "$(date +%s)-$$")"

  # Build JSON payload
  local json=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "trace_id": "$trace_id",
  "container": "$CONTAINER_NAME",
  "action": "$action",
  "status": "$status",
  "message": "$message",
  "user": "$user",
  "host": "$(hostname)",
  "pid": $$
}
EOF
  )

  # Write to log file
  echo "$json" >> "$LOG_FILE"

  # Also log to syslog if available
  if command -v logger >/dev/null 2>&1; then
    echo "$json" | logger -t "runner-audit[$action/$status]" -p daemon.info || true
  fi

  # Debug output if enabled
  if [[ "$DEBUG" -eq 1 ]]; then
    echo "[AUDIT] $action/$status: $message" >&2
  fi
}

monitor_container() {
  local start_time=$(date +%s)
  log_json "monitor_start" "success" "Starting audit monitoring for container $CONTAINER_NAME"

  while true; do
    # Check if container is running
    if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
      container_state=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")

      case "$container_state" in
        running)
          # Check logs for runner status messages
          docker logs "$CONTAINER_NAME" 2>/dev/null | tail -20 | grep -i "listening\|online\|error" | while read -r line; do
            if echo "$line" | grep -q -i "listening"; then
              log_json "runner_ready" "success" "Runner is listening for jobs" "$(whoami)"
            elif echo "$line" | grep -q -i "error"; then
              log_json "runner_error" "error" "$line" "$(whoami)"
            fi
          done || true
          ;;
        exited)
          exit_code=$(docker inspect "$CONTAINER_NAME" --format='{{.State.ExitCode}}' 2>/dev/null || echo "unknown")
          log_json "container_exit" "error" "Container exited with code $exit_code" "$(whoami)"
          ;;
        *)
          log_json "container_state_change" "warning" "Container state: $container_state" "$(whoami)"
          ;;
      esac
    else
      log_json "container_missing" "error" "Container $CONTAINER_NAME not found" "$(whoami)"
    fi

    sleep 30
  done
}

monitor_docker_events() {
  # Monitor docker events for runner-related changes (alternative approach)
  log_json "docker_events_start" "success" "Starting docker events monitoring" "$(whoami)"

  docker events --filter "container=$CONTAINER_NAME" --format 'json' 2>/dev/null | while IFS= read -r event; do
    action=$(echo "$event" | jq -r '.Action // "unknown"')
    status=$(echo "$event" | jq -r '.Actor.Attributes.exitCode // "0"')

    case "$action" in
      start|restart|die|kill)
        log_json "docker_event_$action" "info" "Docker event: $action (exit: $status)" "$(whoami)"
        ;;
    esac
  done || log_json "docker_events_fail" "error" "docker events monitoring failed" "$(whoami)"
}

parse_runner_logs() {
  # Parse runner logs for key events and log them
  log_json "log_parser_start" "success" "Starting runner log parsing" "$(whoami)"

  while true; do
    if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Runner listener started"; then
      log_json "runner_listener_started" "success" "Runner listener process started" "$(whoami)"
    fi

    if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Runner connect error"; then
      log_json "runner_connect_error" "error" "Runner failed to connect to GitHub" "$(whoami)"
    fi

    if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Job received"; then
      log_json "job_received" "info" "Job received by runner" "$(whoami)"
    fi

    if docker logs "$CONTAINER_NAME" 2>/dev/null | tail -50 | grep -q "Job completed"; then
      log_json "job_completed" "success" "Job completed" "$(whoami)"
    fi

    sleep 60
  done
}

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

trap 'log_json "audit_shutdown" "success" "Audit monitoring stopped"; exit 0' SIGTERM SIGINT

# ============================================================================
# MAIN
# ============================================================================

main() {
  # Verify container name provided or available
  if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "ERROR: Container $CONTAINER_NAME not found" >&2
    echo "Usage: $0 [--container-name NAME] [--log-file PATH]" >&2
    exit 1
  fi

  # Verify log file is writable
  if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
    exit 1
  fi

  log_json "audit_startup" "success" "Audit logging started for container $CONTAINER_NAME" "$(whoami)"
  log_json "config" "info" "Log file: $LOG_FILE" "$(whoami)"

  # Start monitoring in background (use whichever approach is most stable)
  # Try docker events first (most reliable), fall back to container monitoring
  if docker events --help >/dev/null 2>&1; then
    monitor_docker_events
  else
    monitor_container
  fi
}

# Parse optional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --log-file) LOG_FILE="$2"; shift 2 ;;
    --debug) DEBUG=1; shift ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --container-name NAME    Docker container to monitor (default: elevatediq-github-runner)"
      echo "  --log-file PATH          Log file path (default: /var/log/runner-audit.log)"
      echo "  --debug                  Enable debug output"
      echo "  -h, --help              Show this help message"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

main
