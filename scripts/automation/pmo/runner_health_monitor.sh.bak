#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Runner Health Monitor
# Continuously monitors self-hosted runner health and auto-restarts on failure
# Designed for both manual execution and systemd timer scheduling
#
# Usage:
#   ./runner_health_monitor.sh [OPTIONS]
#
# Options:
#   --check-once         Run a single health check and exit
#   --install            Install systemd service/timer (user-level)
#   --uninstall          Remove systemd service/timer
#   --status             Show current runner status
#   --logs               Show recent health monitor logs
#   -h, --help           Show this help message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/runner_health_monitor.log"
CONFIG_FILE="${SCRIPT_DIR}/.runner_health_config"
RUNNER_DIR="${HOME}/actions-runner"

# Create log directory
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Check if runner service is active
check_runner_status() {
  local runner_service="actions.runner.*"
  
  if systemctl list-units --all --type=service | grep -q "$runner_service"; then
    systemctl is-active --quiet "$runner_service" && return 0 || return 1
  fi
  
  return 1
}

# Attempt to restart runner with exponential backoff
restart_runner() {
  log "Attempting to restart runner..."
  
  local backoff_seconds=10
  local max_attempts=5
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    
    log "Restart attempt $attempt/$max_attempts (backoff: ${backoff_seconds}s)"
    
    if systemctl start 'actions.runner.*' 2>&1 | tee -a "$LOG_FILE"; then
      sleep 5
      if check_runner_status; then
        log "✓ Runner successfully restarted"
        return 0
      fi
    fi
    
    sleep "$backoff_seconds"
    backoff_seconds=$((backoff_seconds * 2))
  done
  
  log "✗ Failed to restart runner after $max_attempts attempts"
  return 1
}

# Verify runner is online via GitHub API
verify_github_api() {
  local owner="${GITHUB_OWNER:-}"
  local token="${GITHUB_TOKEN:-}"
  
  if [ -z "$owner" ] || [ -z "$token" ]; then
    log "⚠ GitHub API verification skipped (env vars not set)"
    return 0
  fi
  
  local response
  response=$(curl -s -H "Authorization: token $token" \
    "https://api.github.com/orgs/$owner/actions/runners" 2>/dev/null | grep -q "\"online\":true" && echo "0" || echo "1")
  
  [ "$response" = "0" ] && return 0 || return 1
}

# Single health check
check_health() {
  log "=== Health Check Started ==="
  
  if ! check_runner_status; then
    log "✗ Runner is not running"
    if ! restart_runner; then
      log "✗ Failed to restart runner"
      create_github_issue "Runner Health Alert" "Runner failed to restart after multiple attempts"
      return 1
    fi
  fi
  
  if ! verify_github_api; then
    log "⚠ GitHub API verification failed"
  fi
  
  log "=== Health Check Completed ==="
  return 0
}

# Create GitHub issue for persistent failures
create_github_issue() {
  local title="$1"
  local body="$2"
  local owner="${GITHUB_OWNER:-}"
  local repo="${GITHUB_REPO:-}"
  local token="${GITHUB_TOKEN:-}"
  
  if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$token" ]; then
    log "⚠ Unable to create GitHub issue (env vars not set)"
    return 1
  fi
  
  local payload=$(cat <<EOF
{
  "title": "$title",
  "body": "$body\\n\\n**Timestamp:** $(date -Iseconds)\\n**Hostname:** $(hostname)",
  "labels": ["runner-health", "automated", "priority-p1"]
}
EOF
)
  
  curl -s -X POST \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$owner/$repo/issues" \
    -d "$payload" > /dev/null 2>&1 || log "⚠ Failed to create GitHub issue"
}

# Install systemd service/timer
install_systemd() {
  log "Installing systemd service/timer..."
  
  mkdir -p ~/.config/systemd/user/
  
  # Copy service and timer files
  cp "$SCRIPT_DIR/systemd/elevatediq-runner-health-monitor.service" \
    ~/.config/systemd/user/
  cp "$SCRIPT_DIR/systemd/elevatediq-runner-health-monitor.timer" \
    ~/.config/systemd/user/
  
  # Reload and enable
  systemctl --user daemon-reload
  systemctl --user enable elevatediq-runner-health-monitor.timer
  systemctl --user start elevatediq-runner-health-monitor.timer
  
  log "✓ Systemd timer installed and started"
  systemctl --user status elevatediq-runner-health-monitor.timer
}

# Uninstall systemd service/timer
uninstall_systemd() {
  log "Uninstalling systemd service/timer..."
  
  systemctl --user stop elevatediq-runner-health-monitor.timer || true
  systemctl --user disable elevatediq-runner-health-monitor.timer || true
  
  rm -f ~/.config/systemd/user/elevatediq-runner-health-monitor.{service,timer}
  systemctl --user daemon-reload
  
  log "✓ Systemd timer uninstalled"
}

# Show help
show_help() {
  grep '^#' "$0" | grep -E '^\s*#\s+(Usage|Options|Dependencies)' -A 100 | head -20
}

# Main
main() {
  case "${1:-}" in
    --check-once)
      check_health
      ;;
    --install)
      install_systemd
      ;;
    --uninstall)
      uninstall_systemd
      ;;
    --status)
      check_runner_status && echo "✓ Runner is running" || echo "✗ Runner is not running"
      ;;
    --logs)
      tail -f "$LOG_FILE"
      ;;
    -h|--help|"")
      show_help
      ;;
    *)
      log "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
}

trap 'log "Signal received, exiting"; exit 130' SIGINT SIGTERM

main "$@"

