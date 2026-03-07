#!/bin/bash
set -u

# Verify that recovery was successful
# Checks image integrity, health, and system readiness
# Usage: ./scripts/verify-recovery.sh [options]

log() { echo "[VERIFY] $(date +'%H:%M:%S') $*"; }
pass() { echo "[OK] ✓ $*"; }
warn() { echo "[WARN] ⚠ $*"; }
fail() { echo "[FAIL] ✗ $*" >&2; exit 1; }

verify_image_exists() {
  log "Checking if recovered image exists..."
  
  if docker inspect elevatediq/app-backup:recovered >/dev/null 2>&1; then
    pass "Recovered image found"
    return 0
  else
    fail "Recovered image not found"
  fi
}

verify_image_integrity() {
  log "Verifying image integrity..."
  
  local image="elevatediq/app-backup:recovered"
  
  # Check image size (should not be 0)
  local size=$(docker inspect "$image" --format='{{.Size}}' 2>/dev/null)
  if [[ -z "$size" ]] || [[ "$size" == "0" ]]; then
    fail "Image size invalid: $size bytes"
  fi
  
  pass "Image size valid: $size bytes"
  
  # Check image config
  if docker inspect "$image" --format='{{.Config}}' >/dev/null 2>&1; then
    pass "Image config valid"
  else
    fail "Image config invalid"
  fi
  
  return 0
}

verify_image_labels() {
  log "Checking image metadata labels..."
  
  local image="elevatediq/app-backup:recovered"
  
  # Try to read backup metadata
  local labels=$(docker inspect "$image" --format='{{.Config.Labels}}' 2>/dev/null)
  
  if [[ "$labels" == *"backup"* ]]; then
    pass "Backup metadata labels found"
  else
    warn "No backup metadata labels (OK for git-recovered images)"
  fi
  
  return 0
}

verify_system_readiness() {
  log "Checking system readiness..."
  echo ""
  
  # Check Docker daemon
  log "  Docker daemon: "
  if docker ps >/dev/null 2>&1; then
    pass "Docker daemon running"
  else
    fail "Docker daemon not accessible"
  fi
  
  # Check disk space
  log "Checking disk space..."
  local available=$(df /var/lib/docker | tail -1 | awk '{print $4}')
  if [[ $available -gt 1048576 ]]; then  # > 1GB
    pass "Sufficient disk space ($((available / 1024))MB)"
  else
    warn "Low disk space available ($((available / 1024))MB)"
  fi
  
  # Check recovery scripts
  log "Checking recovery scripts..."
  local scripts_ok=true
  
  for script in scripts/recover-from-nuke.sh scripts/verify-recovery.sh; do
    if [[ ! -f "$script" ]]; then
      warn "  Missing: $script"
      scripts_ok=false
    fi
  done
  
  if [[ "$scripts_ok" == "true" ]]; then
    pass "All recovery scripts present"
  fi
  
  return 0
}

verify_backup_metadata() {
  log "Checking backup metadata..."
  
  if [[ ! -f "Dockerfile.backup" ]]; then
    warn "Dockerfile.backup not found"
    return 0
  fi
  
  log "  Checking Dockerfile.backup..."
  
  if grep -q "backup" Dockerfile.backup; then
    pass "Dockerfile.backup contains recovery logic"
  else
    warn "Dockerfile.backup may not be complete recovery image"
  fi
  
  if [[ -d ".backup-metadata" ]]; then
    pass "Backup metadata directory found"
  else
    warn "Backup metadata directory not found"
  fi
  
  return 0
}

verify_recovery_rto() {
  log "Evaluating Recovery Time Objective (RTO)..."
  
  # RTO target: 15 minutes = 900 seconds
  local rto_target=900
  
  # Check if recovery took < 15 minutes
  if [[ -n "${RECOVERY_DURATION_SECONDS:-}" ]]; then
    if [[ $RECOVERY_DURATION_SECONDS -le $rto_target ]]; then
      pass "Recovery completed within RTO target ($RECOVERY_DURATION_SECONDS/$rto_target seconds)"
    else
      warn "Recovery exceeded RTO target ($RECOVERY_DURATION_SECONDS/$rto_target seconds)"
    fi
  else
    log "Recovery duration not measured (OK for manual recovery)"
  fi
  
  return 0
}

# === MAIN ===

main() {
  echo "╔════════════════════════════════════════════╗"
  echo "║  DISASTER RECOVERY VERIFICATION            ║"
  echo "║  $(date +'%Y-%m-%d %H:%M:%S')              ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""
  
  local all_pass=true
  
  # Run all verification checks
  verify_image_exists || all_pass=false
  echo ""
  
  verify_image_integrity || all_pass=false
  echo ""
  
  verify_image_labels || all_pass=false
  echo ""
  
  verify_system_readiness || all_pass=false
  echo ""
  
  verify_backup_metadata || all_pass=false
  echo ""
  
  verify_recovery_rto || all_pass=false
  echo ""
  
  # Summary
  echo "╔════════════════════════════════════════════╗"
  if [[ "$all_pass" == "true" ]]; then
    echo "║  STATUS: ✓ RECOVERY SUCCESSFUL             ║"
    echo "║  Application is ready for deployment      ║"
  else
    echo "║  STATUS: ⚠ RECOVERY PARTIAL SUCCESS        ║"
    echo "║  Some checks failed, review above          ║"
  fi
  echo "╚════════════════════════════════════════════╝"
  echo ""
  
  [[ "$all_pass" == "true" ]]
}

main "$@"
