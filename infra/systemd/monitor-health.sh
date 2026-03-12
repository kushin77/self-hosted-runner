#!/bin/bash
# ==================================================================
# PHASE 1 MONITORING & HEALTH CHECK
# ==================================================================
# Purpose: Monitor deployer key rotation automation health
# Run periodically: crontab -e -> 0 */4 * * * bash /path/to/monitor.sh
# ==================================================================

set -euo pipefail

REPORT_FILE="logs/systemd-deployment/health-check-$(date +%Y%m%d-%H%M%S).jsonl"
mkdir -p "$(dirname $REPORT_FILE)"

# Create JSON entry function
log_entry() {
  local level="$1"
  local message="$2"
  printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$message" >> "$REPORT_FILE"
}

# ==================================================================
# HEALTH CHECK 1: Timer Status
# ==================================================================
TIMER_STATUS=$(sudo systemctl is-active deployer-key-rotate.timer 2>/dev/null || echo "unknown")

if [ "$TIMER_STATUS" = "active" ]; then
  log_entry "INFO" "Timer health: ACTIVE"
else
  log_entry "CRITICAL" "Timer health: $TIMER_STATUS (may need restart)"
fi

# ==================================================================
# HEALTH CHECK 2: Service Status
# ==================================================================
SERVICE_ENABLED=$(sudo systemctl is-enabled deployer-key-rotate.service 2>/dev/null || echo "unknown")

if [ "$SERVICE_ENABLED" = "enabled" ]; then
  log_entry "INFO" "Service enabled: Yes"
else
  log_entry "WARN" "Service enabled: $SERVICE_ENABLED"
fi

# ==================================================================
# HEALTH CHECK 3: Last Rotation Age
# ==================================================================
if [ -d "logs/multi-cloud-audit" ]; then
  LATEST_ROTATION=$(ls -t logs/multi-cloud-audit/owner-rotate-*.jsonl 2>/dev/null | head -1 || echo "")
  
  if [ -n "$LATEST_ROTATION" ]; then
    MTIME=$(stat -c %Y "$LATEST_ROTATION" 2>/dev/null || stat -f %m "$LATEST_ROTATION")
    NOW=$(date +%s)
    AGE=$((NOW - MTIME))
    HOURS=$((AGE / 3600))
    
    if [ "$HOURS" -lt 30 ]; then
      log_entry "INFO" "Last rotation: $HOURS hours ago (healthy)"
    else
      log_entry "WARN" "Last rotation: $HOURS hours ago (no recent rotations)"
    fi
  else
    log_entry "INFO" "No rotations yet (service may be new)"
  fi
else
  log_entry "WARN" "Audit directory not found"
fi

# ==================================================================
# HEALTH CHECK 4: Systemd Timer next run
# ==================================================================
NEXT_RUN=$(sudo systemctl list-timers deployer-key-rotate.timer --no-pager | grep deployer | awk '{print $1}' || echo "unknown")
log_entry "INFO" "Next scheduled run: $NEXT_RUN"

# ==================================================================
# HEALTH CHECK 5: Recent errors
# ==================================================================
RECENT_ERRORS=$(sudo journalctl -u deployer-key-rotate.service --since="24 hours ago" --grep="ERROR" --no-pager -n 1 || echo "none")

if [ "$RECENT_ERRORS" = "none" ]; then
  log_entry "INFO" "Recent errors: None"
else
  log_entry "WARN" "Recent errors: $RECENT_ERRORS"
fi

# ==================================================================
# Summary
# ==================================================================
echo "Health check saved: $REPORT_FILE"
cat "$REPORT_FILE" | jq '.' 2>/dev/null || cat "$REPORT_FILE"
