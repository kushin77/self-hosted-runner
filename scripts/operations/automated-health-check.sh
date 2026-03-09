#!/bin/bash
# Automated Health Checker - Runs continuously in background
set -euo pipefail

HEALTH_CHECK_LOG=".monitoring-hub/health-check.log"
CHECK_INTERVAL=3600  # Every hour

echo "[$(date)] Starting automated health checker..." >> "$HEALTH_CHECK_LOG"

while true; do
  # Run metrics collection
  bash .monitoring-hub/metrics/sla-tracker.sh >> "$HEALTH_CHECK_LOG" 2>&1 || true
  bash .monitoring-hub/metrics/vulnerability-detector.sh >> "$HEALTH_CHECK_LOG" 2>&1 || true
  
  # Check alert rules
  check_alert_rules >> "$HEALTH_CHECK_LOG" 2>&1 || true
  
  # Log timestamp
  echo "[$(date)] Health check completed" >> "$HEALTH_CHECK_LOG"
  
  # Wait for next check
  sleep "$CHECK_INTERVAL"
done
