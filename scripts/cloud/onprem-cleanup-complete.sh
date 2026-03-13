#!/usr/bin/env bash
set -euo pipefail

# On-prem cleanup: stop local services, containers, and compose stacks.
# Default is dry-run for safety.

DRY_RUN=${DRY_RUN:-true}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/cleanup"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOGFILE="${LOGFILE:-${LOG_DIR}/onprem-cleanup-${TIMESTAMP}.jsonl}"
ERROR_FILE="${ERROR_FILE:-${LOG_DIR}/onprem-cleanup-errors-${TIMESTAMP}.jsonl}"

mkdir -p "${LOG_DIR}"

log() {
  local level="$1"
  local message="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
      --arg level "$level" \
      --arg message "$message" \
      '{timestamp:$ts,level:$level,message:$message}' >> "$LOGFILE"
  else
    printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$message" >> "$LOGFILE"
  fi
}

log_error() {
  local message="$1"
  log "ERROR" "$message"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
      --arg message "$message" \
      '{timestamp:$ts,error:$message,source:"onprem-cleanup"}' >> "$ERROR_FILE"
  else
    printf '%s ERROR %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" >> "$ERROR_FILE"
  fi
}

run_cmd() {
  local description="$1"
  shift
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: ${description}"
    log "INFO" "dry_run ${description}"
    return 0
  fi

  if "$@"; then
    log "INFO" "success ${description}"
    return 0
  fi

  log_error "failed ${description}"
  return 1
}

stop_systemd_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "WARN" "systemctl not available; skipping service stop"
    return 0
  fi

  local services=(
    docker.service
    containerd.service
    redis.service
    postgresql.service
    gitlab-runner.service
    cloudrun.service
    redis-worker.service
    canonical-secrets-api.service
  )

  for svc in "${services[@]}"; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
      run_cmd "systemctl stop ${svc}" systemctl stop "$svc" || true
    fi
  done
}

stop_compose_stacks() {
  local compose_files
  compose_files=$(find "$REPO_ROOT" -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.*.yml' -o -name 'docker-compose.*.yaml' \) 2>/dev/null || true)
  if [ -z "$compose_files" ]; then
    log "INFO" "no docker compose files found"
    return 0
  fi

  while IFS= read -r compose_file; do
    [ -z "$compose_file" ] && continue
    run_cmd "docker compose down -f ${compose_file}" docker compose -f "$compose_file" down --remove-orphans || true
  done <<< "$compose_files"
}

stop_containers() {
  if ! command -v docker >/dev/null 2>&1; then
    log "WARN" "docker not found; skipping container stop"
    return 0
  fi

  local running
  running=$(docker ps -q 2>/dev/null || true)
  if [ -z "$running" ]; then
    log "INFO" "no running containers"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: would stop containers"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    log "INFO" "dry_run docker_stop_all"
    return 0
  fi

  if docker stop $running >/dev/null 2>&1; then
    log "INFO" "stopped_all_running_containers"
  else
    log_error "docker stop failed for one or more containers"
  fi
}

echo "On-prem cleanup start (dry-run=${DRY_RUN})"
log "INFO" "onprem_cleanup_start dry_run=${DRY_RUN}"

stop_systemd_services
stop_compose_stacks
stop_containers

log "INFO" "onprem_cleanup_end"
echo "On-prem cleanup complete (dry-run=${DRY_RUN})"
