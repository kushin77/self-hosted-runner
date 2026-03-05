#!/usr/bin/env bash
##
## Health Check & Self-Healing
## Monitors runner health and initiates self-healing.
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"
LOG_FILE="/var/log/runner-health.log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Check runner process
check_runner_running() {
  if systemctl is-active --quiet actions-runner; then
    log "✓ Runner service active"
    return 0
  else
    log "✗ Runner service inactive"
    return 1
  fi
}

# Check disk usage
check_disk_space() {
  USAGE=$(df "${RUNNER_HOME}" | awk 'NR==2 {print $5}' | sed 's/%//')
  
  if [ "${USAGE}" -gt 90 ]; then
    log "✗ Disk usage critical: ${USAGE}%"
    return 1
  elif [ "${USAGE}" -gt 80 ]; then
    log "⚠ Disk usage high: ${USAGE}%"
    return 0
  else
    log "✓ Disk usage OK: ${USAGE}%"
    return 0
  fi
}

# Check memory
check_memory() {
  USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
  
  if [ "${USAGE}" -gt 90 ]; then
    log "✗ Memory usage critical: ${USAGE}%"
    return 1
  else
    log "✓ Memory usage OK: ${USAGE}%"
    return 0
  fi
}

# Check network connectivity
check_network() {
  if curl -s --connect-timeout 5 https://api.github.com >/dev/null; then
    log "✓ Network connectivity OK"
    return 0
  else
    log "✗ Network connectivity failed"
    return 1
  fi
}

# Check for zombie processes
check_zombie_processes() {
  ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /Z/ {count++} END {print count}' || echo 0)
  
  if [ "${ZOMBIE_COUNT}" -gt 10 ]; then
    log "⚠ Found ${ZOMBIE_COUNT} zombie processes"
    return 1
  else
    log "✓ No zombie processes"
    return 0
  fi
}

# Check Docker daemon
check_docker() {
  if docker ps >/dev/null 2>&1; then
    log "✓ Docker daemon healthy"
    return 0
  else
    log "✗ Docker daemon failed"
    return 1
  fi
}

# Clean up old containers
cleanup_containers() {
  log "Cleaning up old containers..."
  docker container prune -f --filter "until=24h" || true
  docker image prune -f --filter "until=24h" || true
  log "✓ Container cleanup completed"
}

# Clean up old jobs
cleanup_old_jobs() {
  log "Cleaning up old job workspaces..."
  find "${RUNNER_HOME}" -name "_work" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
  log "✓ Job cleanup completed"
}

# Restart unhealthy runner
restart_runner() {
  log "⚠ Restarting runner service..."
  systemctl restart actions-runner
  sleep 5
  
  if systemctl is-active --quiet actions-runner; then
    log "✓ Runner restarted successfully"
    return 0
  else
    log "✗ Runner restart failed"
    return 1
  fi
}

# Self-healing: quarantine and destroy unhealthy runner
self_heal() {
  log "⚠ Self-healing triggered: runner is unhealthy"
  
  # Drain runner of jobs
  log "Draining runner..."
  curl -X POST "${RUNNER_MGMT_URL}/api/runners/$(hostname)/drain" \
    -H "Authorization: Bearer ${RUNNER_TOKEN}" || true
  
  sleep 30
  
  # Attempt restart
  if restart_runner; then
    return 0
  fi
  
  # If restart failed, quarantine and signal for replacement
  log "✗ Self-healing failed, quarantining runner"
  
  touch "${RUNNER_HOME}/.quarantined"
  curl -X POST "${RUNNER_MGMT_URL}/api/runners/$(hostname)/quarantine" \
    -H "Authorization: Bearer ${RUNNER_TOKEN}" || true
  
  # Notify ops team
  echo "Runner $(hostname) is quarantined and requires manual intervention" | \
    mail -s "Runner Health Alert" ops@example.com || true
  
  return 1
}

# Main health check routine
main() {
  log "Starting health check..."
  
  local health_score=0
  
  check_runner_running || ((health_score++))
  check_network || ((health_score++))
  check_disk_space || ((health_score++))
  check_memory || ((health_score++))
  check_docker || ((health_score++))
  check_zombie_processes || ((health_score++))
  
  cleanup_containers
  cleanup_old_jobs
  
  log "Health score: ${health_score}/6"
  
  if [ "${health_score}" -gt 2 ]; then
    log "⚠ Runner health degraded"
    self_heal
  elif [ "${health_score}" -eq 0 ]; then
    log "✓ All health checks passed"
  fi
}

# If run with --daemon flag, loop continuously
if [ "${1:-}" == "--daemon" ]; then
  INTERVAL="${2:-300}"  # 5 minutes default
  while true; do
    main
    sleep "${INTERVAL}"
  done
else
  main
fi
