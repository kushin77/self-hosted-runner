#!/bin/bash
#
# 🏥 NAS SERVER HEALTH CHECK - WORKER NODE
#
# Validates worker node's NAS connectivity and sync status
# Used by systemd timer for continuous monitoring
#
# Status codes:
#   0 = All healthy
#   1 = Critical failure
#   2 = Warning state
#
# Usage:
#   bash healthcheck-worker-nas.sh
#   bash healthcheck-worker-nas.sh --verbose

set -euo pipefail

# Configuration
readonly NAS_HOST="${NAS_HOST:-192.168.168.100}"
readonly NAS_PORT="${NAS_PORT:-22}"
readonly NAS_USER="${NAS_USER:-svc-nas}"
readonly WORKER_SYNC_BASE="${WORKER_SYNC_BASE:-/opt/nas-sync}"
readonly HEALTHCHECK_LOG="${HEALTHCHECK_LOG:-/var/log/nas-integration/worker-health.log}"
readonly VERBOSE="${VERBOSE:-false}"

# SSH options
readonly SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"

# Thresholds
readonly MAX_SYNC_AGE_SECONDS=3600     # 1 hour
readonly MAX_DISK_USAGE_PERCENT=85     # 85%
readonly MIN_SYNC_INTERVAL=60           # 60 seconds

# ============================================================================
# LOGGING
# ============================================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$HEALTHCHECK_LOG"
}

verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    log "DEBUG: $*"
  fi
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

check_nas_connectivity() {
  verbose "Checking NAS connectivity..."
  
  if ssh -i /home/automation/.ssh/id_ed25519 $SSH_OPTS -p "$NAS_PORT" \
       "${NAS_USER}@${NAS_HOST}" echo "connectivity-check" &>/dev/null; then
    log "✅ NAS connectivity OK"
    return 0
  else
    log "❌ NAS connectivity FAILED"
    return 1
  fi
}

check_sync_directories() {
  verbose "Checking sync directory structure..."
  
  local errors=0
  
  for dir in "$WORKER_SYNC_BASE"/{iac,configs,credentials,audit}; do
    if [[ ! -d "$dir" ]]; then
      log "❌ Missing sync directory: $dir"
      ((errors++))
    fi
  done
  
  if [[ $errors -eq 0 ]]; then
    log "✅ Sync directories OK"
    return 0
  else
    log "⚠️  Found $errors missing directories"
    return 2
  fi
}

check_last_sync_time() {
  verbose "Checking last successful sync..."
  
  local last_success_file="${WORKER_SYNC_BASE}/audit/.last-success"
  
  if [[ ! -f "$last_success_file" ]]; then
    log "⚠️  No sync history found (first run?)"
    return 0
  fi
  
  local last_sync_epoch=$(<"$last_success_file")
  local current_epoch=$(date +%s)
  local elapsed=$((current_epoch - last_sync_epoch))
  
  if [[ $elapsed -lt $MAX_SYNC_AGE_SECONDS ]]; then
    log "✅ Last sync: ${elapsed}s ago"
    return 0
  else
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    log "⚠️  Sync stale: ${hours}h ${minutes}m ago (threshold: 1h)"
    return 2
  fi
}

check_sync_integrity() {
  verbose "Checking sync content integrity..."
  
  local errors=0
  
  # Check IAC directory has content
  if [[ -z "$(find "$WORKER_SYNC_BASE/iac" -type f -not -path '*/\.*' 2>/dev/null | head -1)" ]]; then
    log "⚠️  IAC directory is empty"
    ((errors++))
  fi
  
  # Check for corrupt or partial files
  if find "$WORKER_SYNC_BASE" -type f -size 0 2>/dev/null | grep -q .; then
    log "⚠️  Found zero-sized files (potential corruption)"
    ((errors++))
  fi
  
  # Verify permissions on sensitive directories
  local cred_perms=$(stat -f%OLp "$WORKER_SYNC_BASE/credentials" 2>/dev/null || stat -c%a "$WORKER_SYNC_BASE/credentials" 2>/dev/null)
  if [[ "${cred_perms: -3}" != "700" ]]; then
    log "⚠️  Credentials directory has incorrect permissions: $cred_perms (should be 700)"
    ((errors++))
  fi
  
  if [[ $errors -eq 0 ]]; then
    log "✅ Sync integrity OK"
    return 0
  else
    log "⚠️  Found $errors integrity issues"
    return 2
  fi
}

check_disk_usage() {
  verbose "Checking disk usage..."
  
  # Get sync directory size
  local sync_size=$(du -sh "$WORKER_SYNC_BASE" 2>/dev/null | awk '{print $1}')
  log "✅ Sync directory size: $sync_size"
  
  # Check if mounted filesystem has space
  local mount_point=$(df "$WORKER_SYNC_BASE" | tail -1 | awk '{print $NF}')
  local usage_percent=$(df "$WORKER_SYNC_BASE" | tail -1 | awk '{print $(NF-1)}' | sed 's/%//')
  
  if [[ $usage_percent -ge $MAX_DISK_USAGE_PERCENT ]]; then
    log "⚠️  Disk usage high: ${usage_percent}% (threshold: ${MAX_DISK_USAGE_PERCENT}%)"
    return 2
  else
    log "✅ Disk usage OK: ${usage_percent}%"
    return 0
  fi
}

check_sync_audit_trail() {
  verbose "Checking audit trail..."
  
  local audit_trail="${WORKER_SYNC_BASE}/audit/sync-audit-trail.jsonl"
  
  if [[ ! -f "$audit_trail" ]]; then
    log "⚠️  No audit trail found"
    return 0
  fi
  
  # Count recent successful syncs (last 24 hours)
  local recent_successes=$(jq -s 'map(select(.status == "SUCCESS" and (.timestamp | fromdateiso8601 > now - 86400))) | length' "$audit_trail" 2>/dev/null || echo "0")
  
  if [[ $recent_successes -gt 0 ]]; then
    log "✅ Recent syncs: $recent_successes (last 24h)"
    return 0
  else
    log "⚠️  No successful syncs in last 24 hours"
    return 2
  fi
}

# ============================================================================
# GENERATE HEALTH REPORT
# ============================================================================

generate_health_report() {
  log "════════════════════════════════════════════════════════════"
  log "🏥 NAS Worker Node Health Report"
  log "════════════════════════════════════════════════════════════"
  log "Time: $(date)"
  log "Hostname: $(hostname)"
  log "NAS Target: ${NAS_USER}@${NAS_HOST}:${NAS_PORT}"
  log "Sync Base: $WORKER_SYNC_BASE"
  log "────────────────────────────────────────────────────────────"
}

# ============================================================================
# MAIN HEALTH CHECK
# ============================================================================

main() {
  local exit_code=0
  
  mkdir -p "$(dirname "$HEALTHCHECK_LOG")"
  
  generate_health_report
  
  # Run all checks
  check_nas_connectivity || ((exit_code+=$?))
  check_sync_directories || ((exit_code+=$?))
  check_last_sync_time || ((exit_code+=$?))
  check_sync_integrity || ((exit_code+=$?))
  check_disk_usage || ((exit_code+=$?))
  check_sync_audit_trail || ((exit_code+=$?))
  
  log "════════════════════════════════════════════════════════════"
  
  # Determine overall status
  if [[ $exit_code -eq 0 ]]; then
    log "🟢 Overall Status: HEALTHY"
  elif [[ $exit_code -eq 2 ]]; then
    log "🟡 Overall Status: WARNING (some issues detected)"
  else
    log "🔴 Overall Status: CRITICAL (failures detected)"
  fi
  
  log "════════════════════════════════════════════════════════════"
  
  return $exit_code
}

main "$@"
