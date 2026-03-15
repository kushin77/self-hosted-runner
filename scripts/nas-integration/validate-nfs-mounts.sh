#!/bin/bash
#
# 🔍 NFS MOUNT VALIDATION & AUTO-REPAIR SCRIPT
#
# Continuously checks NFS mount health and auto-repairs stale mounts
#
# Usage:
#   bash validate-nfs-mounts.sh [--verbose] [--repair]
#

set -euo pipefail

readonly NAS_IP="${NAS_IP:-192.168.168.100}"
readonly LOCAL_MOUNT_BASE="/mnt/nas"
readonly LOCAL_REPOSITORIES="${LOCAL_MOUNT_BASE}/repositories"
readonly LOCAL_CONFIG_VAULT="${LOCAL_MOUNT_BASE}/config-vault"
readonly LOCAL_AUDIT_LOGS="${LOCAL_MOUNT_BASE}/audit-logs"

readonly LOG_DIR="/var/log/nas-integration"
readonly VALIDATE_LOG="${LOG_DIR}/nfs-validate.log"
readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Options
VERBOSE="${1:-}"
AUTO_REPAIR="${2:-}"

# ============================================================================
# LOGGING
# ============================================================================

log() { echo "[${TIMESTAMP}] $*" >> "$VALIDATE_LOG"; }
info() { echo -e "${GREEN}ℹ${NC}  $*"; log "INFO: $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*" >&2; log "WARN: $*"; }
error() { echo -e "${RED}✗${NC}  $*" >&2; log "ERROR: $*"; }

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

check_mount_responsive() {
  local mount_point="$1"
  local timeout=5
  
  if [[ ! -d "$mount_point" ]]; then
    return 2  # Mount point doesn't exist
  fi
  
  # Try to access mount point with timeout
  if timeout "$timeout" ls "$mount_point" &>/dev/null; then
    return 0  # Mount is responsive
  else
    return 1  # Mount is unresponsive (likely stale)
  fi
}

check_nfs_processes() {
  # Check if NFS client processes are running
  if pgrep -f "nfs" &>/dev/null; then
    return 0  # NFS processes active
  else
    return 1  # No NFS processes
  fi
}

check_nas_connectivity() {
  # Quick ping to NAS
  if timeout 5 ping -c 1 "$NAS_IP" &>/dev/null; then
    return 0  # NAS reachable
  else
    return 1  # NAS unreachable
  fi
}

# ============================================================================
# REPAIR FUNCTIONS
# ============================================================================

force_unmount() {
  local mount_point="$1"
  
  if [[ ! -d "$mount_point" ]] || ! mountpoint -q "$mount_point"; then
    return 0
  fi
  
  warn "Force unmounting $mount_point..."
  
  # Try lazy unmount first (doesn't fail on stale NFS)
  if umount -l "$mount_point" 2>/dev/null; then
    info "Lazy unmounted $mount_point"
    return 0
  fi
  
  # Try force unmount
  if umount -f "$mount_point" 2>/dev/null; then
    info "Force unmounted $mount_point"
    return 0
  fi
  
  error "Could not unmount $mount_point"
  return 1
}

remount() {
  local mount_point="$1"
  
  # Unmount first
  force_unmount "$mount_point" || true
  
  sleep 1
  
  # Try to remount via systemd
  if systemctl is-active --quiet "mnt-nas-$(basename $mount_point).mount"; then
    systemctl restart "mnt-nas-$(basename $mount_point).mount" || true
  fi
  
  # Try manual mount from fstab
  if grep -q "$mount_point" /etc/fstab 2>/dev/null; then
    mount "$mount_point" 2>/dev/null || true
  fi
  
  # Verify
  sleep 1
  if mountpoint -q "$mount_point"; then
    info "Remounted $mount_point successfully"
    return 0
  else
    return 1
  fi
}

# ============================================================================
# MAIN VALIDATION LOOP
# ============================================================================

validate_all() {
  local status=0
  
  log "===== NFS Mount Validation ====="
  
  # Check NAS connectivity first
  if ! check_nas_connectivity; then
    warn "NAS ($NAS_IP) is unreachable - skipping mount checks"
    log "NAS unreachable - repair not possible"
    return 1
  fi
  
  info "NAS connectivity verified"
  
  # Check each mount
  for mount_point in "$LOCAL_REPOSITORIES" "$LOCAL_CONFIG_VAULT" "$LOCAL_AUDIT_LOGS"; do
    local mount_name=$(basename "$mount_point")
    
    if ! mountpoint -q "$mount_point"; then
      warn "Mount $mount_name is NOT active"
      ((status++))
      
      if [[ "$AUTO_REPAIR" == "--repair" ]]; then
        info "Attempting to repair $mount_name..."
        if remount "$mount_point"; then
          info "✓ Repaired $mount_name"
        else
          error "✗ Could not repair $mount_name"
        fi
      fi
      continue
    fi
    
    # Check if mount is responsive
    if check_mount_responsive "$mount_point"; then
      info "✓ Mount $mount_name is active and responsive"
    else
      warn "Mount $mount_name is STALE (unresponsive)"
      ((status++))
      
      if [[ "$AUTO_REPAIR" == "--repair" ]]; then
        info "Auto-repairing stale mount $mount_name..."
        if remount "$mount_point"; then
          info "✓ Repaired stale mount $mount_name"
        else
          error "✗ Could not repair stale mount $mount_name"
        fi
      fi
    fi
  done
  
  log "Validation complete (status: $status)"
  return $status
}

# ============================================================================
# MAIN
# ============================================================================

mkdir -p "$LOG_DIR"
touch "$VALIDATE_LOG"

if validate_all; then
  exit 0
else
  exit 1
fi
