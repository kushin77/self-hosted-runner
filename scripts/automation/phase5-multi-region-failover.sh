#!/usr/bin/env bash
# Phase 5: Multi-Region Failover Configuration
# Enables automatic failover between primary and secondary runner endpoints

set -euo pipefail

# Region configuration
declare -A REGIONS=(
  [primary]="https://runners.primary.internal"
  [secondary]="https://runners.secondary.internal"
  [tertiary]="https://runners.tertiary.internal"
)

HEALTH_CHECK_INTERVAL=60
HEALTH_CHECK_TIMEOUT=10
FAILURE_THRESHOLD=3

LOG_DIR="${SCRIPT_DIR:-/tmp}/failover_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/failover_$(date +%Y%m%d_%H%M%S).log"

log_message() {
  local level="$1"
  local message="$2"
  echo "[$(date -Iseconds)] [$level] $message" | tee -a "$LOG_FILE"
}

check_region_health() {
  local region="$1"
  local endpoint="$2"
  
  log_message "DEBUG" "Health check: $region ($endpoint)"
  
  set +e
  local response=$(curl -s -w "\n%{http_code}" --connect-timeout "$HEALTH_CHECK_TIMEOUT" "$endpoint/health" 2>&1)
  local http_code=$(echo "$response" | tail -n1)
  set -e
  
  if [ "$http_code" = "200" ]; then
    log_message "INFO" "✓ Region $region is healthy (HTTP $http_code)"
    echo "healthy"
  else
    log_message "WARN" "✗ Region $region unhealthy (HTTP $http_code)"
    echo "unhealthy"
  fi
}

get_active_region() {
  if [ -f "$LOG_DIR/active_region" ]; then
    cat "$LOG_DIR/active_region"
  else
    echo "primary"
  fi
}

set_active_region() {
  local region="$1"
  echo "$region" > "$LOG_DIR/active_region"
  log_message "INFO" "Active region set to: $region"
}

if [ "${1:-}" = "--status" ]; then
  ACTIVE=$(get_active_region)
  for region in "${!REGIONS[@]}"; do
    local endpoint="${REGIONS[$region]}"
    local health=$(check_region_health "$region" "$endpoint")
    local status=$([ "$health" = "healthy" ] && echo "✓ HEALTHY" || echo "✗ UNHEALTHY")
    local active_marker=$([ "$region" = "$ACTIVE" ] && echo " [ACTIVE]" || echo "")
    echo "$region: $status$active_marker"
  done
elif [ "${1:-}" = "--help" ]; then
  cat <<EOF
Multi-Region Failover Configuration
Usage: $(basename "$0") [OPTIONS]

Options:
  --status    Check status of all regions
  --help      Show this help message

Region Configuration:
EOF
  for region in "${!REGIONS[@]}"; do
    echo "  $region: ${REGIONS[$region]}"
  done
else
  log_message "INFO" "Running health check"
  for region in "${!REGIONS[@]}"; do
    local endpoint="${REGIONS[$region]}"
    check_region_health "$region" "$endpoint"
  done
fi
