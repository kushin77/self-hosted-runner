#!/bin/bash
# ElevatedIQ Self-Hosted Runner Cleanup Script
# Purpose: Clean stale temporary files that block workflow execution
# Location: /usr/local/bin/elevatediq-runner-cleanup (deploy via systemd)
# Execution: systemd timer (every 6 hours)
# NIST: SC-7, CA-7, SI-4

set -e

RUNNER_USER="akushnir"
RUNNER_HOME="/home/${RUNNER_USER}"
RUNNER_WORK="${RUNNER_HOME}/ElevatedIQ-Mono-Mono-Repo"
TMP_CLEANUP_PATTERNS=(
  "/tmp/gitleaks*"
  "/tmp/pytest*"
  "/tmp/mypy*"
  "/tmp/coverage*"
  "/tmp/docker*"
  "/tmp/pip*"
)

# Logging
LOG_FILE="/var/log/elevatediq-runner-cleanup.log"
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Pre-flight validation
validate_runner_health() {
  log "🔍 Validating runner health..."
  
  # Check disk usage
  DISK_USAGE=$(df /tmp | awk 'NR==2 {print $5}' | sed 's/%//')
  if [ "$DISK_USAGE" -gt 70 ]; then
    log "⚠️  WARNING: /tmp usage at ${DISK_USAGE}% (threshold: 70%)"
  else
    log "✅ /tmp usage: ${DISK_USAGE}% (normal)"
  fi
  
  # Check for stuck processes
  STUCK_PROCESSES=$(ps aux | grep -i gitleaks | grep -v grep | wc -l)
  if [ "$STUCK_PROCESSES" -gt 0 ]; then
    log "⚠️  WARNING: $STUCK_PROCESSES stuck gitleaks processes detected"
  fi
}

# Cleanup stale files
cleanup_stale_files() {
  log "🧹 Cleaning up stale temporary files..."
  
  CLEANED=0
  for PATTERN in "${TMP_CLEANUP_PATTERNS[@]}"; do
    MATCHES=$(find /tmp -name "${PATTERN##*/}" 2>/dev/null | wc -l)
    if [ "$MATCHES" -gt 0 ]; then
      find /tmp -name "${PATTERN##*/}" -type f -mtime +0 -exec rm -f {} \; 2>/dev/null || true
      log "✅ Cleaned $MATCHES files matching pattern: $PATTERN"
      CLEANED=$((CLEANED + MATCHES))
    fi
  done
  
  log "📊 Total files cleaned: $CLEANED"
}

# Runner queue health check
check_queue_health() {
  log "📋 Checking runner queue health..."
  
  if [ -d "${RUNNER_WORK}/.runner" ]; then
    # Count pending jobs
    PENDING=$(find "${RUNNER_WORK}/.runner/_work" -name "*.running" 2>/dev/null | wc -l || echo 0)
    if [ "$PENDING" -gt 5 ]; then
      log "⚠️  WARNING: $PENDING pending jobs detected"
    else
      log "✅ Queue health normal: $PENDING pending jobs"
    fi
  fi
}

# Recovery procedures
recovery_stale_workflow() {
  log "🔧 Checking for stale workflow locks..."
  
  # Remove workflow lock files older than 30 minutes
  find "${RUNNER_WORK}" -name "*.lock" -type f -mmin +30 -exec rm -f {} \; 2>/dev/null || true
  log "✅ Stale workflow locks cleared"
}

# Main execution
main() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🚀 ElevatedIQ Runner Cleanup Starting"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  validate_runner_health
  cleanup_stale_files
  recovery_stale_workflow
  check_queue_health
  
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "✅ Runner Cleanup Complete"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
