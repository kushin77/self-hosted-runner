#!/bin/bash

################################################################################
# Runner Pytest Hygiene Script
#
# Detects and cleans up stuck pytest processes to prevent resource exhaustion
# during parallel test execution.
#
# Usage:
#   ./runner_pytest_hygiene.sh [--check] [--cleanup] [--monitor]
################################################################################

set -euo pipefail

CHECK_MODE=${CHECK_MODE:-false}
CLEANUP_MODE=${CLEANUP_MODE:-false}
MONITOR_MODE=${MONITOR_MODE:-false}
LOG_DIR="/var/log/runner-hygiene"
TIMESTAMP=$(date +%s)
PYTEST_TIMEOUT=3600  # 1 hour

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pytest-hygiene-$TIMESTAMP.log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check for stuck pytest processes
check_pytest_health() {
  log "Checking pytest process health..."
  
  local stuck_count=0
  local total_count=0
  
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    
    local pid=$(echo "$line" | awk '{print $1}')
    local elapsed=$(echo "$line" | awk '{print $2}')
    ((total_count++))
    
    if [[ $elapsed -gt $PYTEST_TIMEOUT ]]; then
      log "STUCK: PID $pid running for ${elapsed}s"
      ((stuck_count++))
    fi
  done < <(pgrep -f "pytest|py.test" -a 2>/dev/null | while read -r line; do
      local pid=$(echo "$line" | awk '{print $1}')
      local elapsed=$((TIMESTAMP - $(stat -c %Y /proc/$pid 2>/dev/null || echo $TIMESTAMP)))
      echo "$pid $elapsed"
    done)
  
  log "Total pytest processes: $total_count, Stuck: $stuck_count"
  return $([[ $stuck_count -eq 0 ]] && echo 0 || echo 1)
}

# Cleanup stuck pytest processes
cleanup_pytest() {
  log "Cleaning up stuck pytest processes..."
  
  local killed_count=0
  
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    
    local elapsed=$((TIMESTAMP - $(stat -c %Y /proc/$pid 2>/dev/null || echo $TIMESTAMP)))
    if [[ $elapsed -gt $PYTEST_TIMEOUT ]]; then
      log "Killing stuck pytest PID: $pid (${elapsed}s elapsed)"
      kill -9 "$pid" 2>/dev/null || true
      ((killed_count++))
    fi
  done < <(pgrep -f "pytest|py.test" 2>/dev/null || true)
  
  log "Pytest processes killed: $killed_count"
}

# Monitor pytest processes continuously
monitor_pytest() {
  log "Starting pytest monitoring (interval: 60s)..."
  
  while true; do
    if ! check_pytest_health; then
      log "Detected stuck processes, running cleanup..."
      cleanup_pytest
    fi
    
    sleep 60
  done
}

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --check)    CHECK_MODE=true ;;
    --cleanup)  CLEANUP_MODE=true ;;
    --monitor)  MONITOR_MODE=true ;;
  esac
done

# Main execution
main() {
  log "Pytest hygiene started (CHECK=$CHECK_MODE, CLEANUP=$CLEANUP_MODE, MONITOR=$MONITOR_MODE)"
  
  if [[ "$CHECK_MODE" == "true" ]]; then
    check_pytest_health
  elif [[ "$CLEANUP_MODE" == "true" ]]; then
    cleanup_pytest
  elif [[ "$MONITOR_MODE" == "true" ]]; then
    monitor_pytest
  else
    # Default: check and cleanup
    check_pytest_health || cleanup_pytest
  fi
  
  # Rotate logs
  find "$LOG_DIR" -name "pytest-hygiene-*.log" -mtime +7 -delete 2>/dev/null || true
  
  log "Pytest hygiene completed"
}

main
