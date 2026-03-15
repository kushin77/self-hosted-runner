#!/bin/bash
#
# 📦 NFS MOUNT MANAGEMENT FOR DEV NODE (192.168.168.31)
#
# Configures Network File System (NFS) mounts to NAS for efficient access
# to shared infrastructure code and configuration repositories
#
# Features:
#   ✅ Automatic NFS mount setup  
#   ✅ Mount point validation
#   ✅ Performance optimization
#   ✅ Failure recovery
#   ✅ Automated remounting on reboot
#   ✅ Health monitoring
#
# Usage:
#   sudo bash setup-nfs-mounts.sh [--mount|--unmount|--remount|--validate|--repair]
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly NAS_HOST="${NAS_HOST:-192.168.168.100}"
readonly NAS_IP="${NAS_IP:-192.168.168.100}"
readonly NAS_PORT="${NAS_PORT:-2049}"
readonly DEV_NODE="${DEV_NODE:-192.168.168.31}"

# NFS Mount Points on NAS
readonly NAS_REPOSITORIES="/home/elevatediq-svc-nas/repositories"
readonly NAS_CONFIG_VAULT="/home/elevatediq-svc-nas/config-vault"
readonly NAS_AUDIT_LOGS="/home/elevatediq-svc-nas/audit-logs"

# Local Mount Points on Dev Node
readonly LOCAL_MOUNT_BASE="/mnt/nas"
readonly LOCAL_REPOSITORIES="${LOCAL_MOUNT_BASE}/repositories"
readonly LOCAL_CONFIG_VAULT="${LOCAL_MOUNT_BASE}/config-vault"
readonly LOCAL_AUDIT_LOGS="${LOCAL_MOUNT_BASE}/audit-logs"
readonly LOCAL_LINK_IAC="/opt/iac-configs-nas"

# NFS Options
readonly NFS_VERSION="nfs4"
readonly NFS_OPTIONS_READ="vers=4.1,proto=tcp,port=2049,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,nolock"
readonly NFS_OPTIONS_WRITE="${NFS_OPTIONS_READ},async"

# Logging
readonly LOG_DIR="/var/log/nas-integration"
readonly NFS_LOG="${LOG_DIR}/nfs-mounts.log"
readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING & VALIDATION
# ============================================================================

log() { echo "[${TIMESTAMP}] INFO: $*" | tee -a "$NFS_LOG"; }
success() { echo -e "${GREEN}✅${NC} $*" | tee -a "$NFS_LOG"; }
warn() { echo -e "${YELLOW}⚠️${NC}  $*" | tee -a "$NFS_LOG" >&2; }
error() { echo -e "${RED}❌${NC} $*" | tee -a "$NFS_LOG" >&2; exit 1; }

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
  fi
}

ensure_log_dir() {
  mkdir -p "$LOG_DIR"
  touch "$NFS_LOG"
}

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

check_prerequisites() {
  log "Checking NFS mount prerequisites..."
  
  # Check NFS utilities
  if ! command -v mount &>/dev/null; then
    error "mount command not found - install util-linux"
  fi
  
  if ! command -v showmount &>/dev/null; then
    warn "showmount not found - NFS utils optional but recommended"
  fi
  
  # Check NAS connectivity
  if ! ping -c 1 "$NAS_IP" &>/dev/null; then
    error "Cannot reach NAS at $NAS_IP - check network connectivity"
  fi
  
  success "Prerequisites check passed"
}

# ============================================================================
# NAS EXPORT VALIDATION
# ============================================================================

validate_nas_exports() {
  log "Validating NAS exports..."
  
  # Show available exports
  if command -v showmount &>/dev/null; then
    local exports=$(showmount -e "$NAS_IP" 2>/dev/null) || {
      warn "Could not query NAS exports - continuing anyway"
      return 0
    }
    
    log "Available NAS exports:"
    echo "$exports" | tee -a "$NFS_LOG"
  fi
  
  success "NAS export validation complete"
}

# ============================================================================
# CREATE MOUNT POINTS
# ============================================================================

create_mount_points() {
  log "Creating local mount point directories..."
  
  mkdir -p "$LOCAL_REPOSITORIES"
  mkdir -p "$LOCAL_CONFIG_VAULT"
  mkdir -p "$LOCAL_AUDIT_LOGS"
  
  # Set permissions
  chmod 755 "$LOCAL_MOUNT_BASE"
  chmod 755 "$LOCAL_REPOSITORIES"
  chmod 755 "$LOCAL_CONFIG_VAULT"
  chmod 700 "$LOCAL_AUDIT_LOGS"
  
  success "Mount points created:"
  success "  - $LOCAL_REPOSITORIES"
  success "  - $LOCAL_CONFIG_VAULT"
  success "  - $LOCAL_AUDIT_LOGS"
}

# ============================================================================
# PERFORM NFS MOUNTS
# ============================================================================

mount_nfs() {
  log "Mounting NFS shares from NAS..."
  
  local mounted=0
  
  # Mount repositories (read-write)
  log "Mounting $NAS_HOST:$NAS_REPOSITORIES to $LOCAL_REPOSITORIES..."
  if mount -t "$NFS_VERSION" "$NAS_IP:$NAS_REPOSITORIES" "$LOCAL_REPOSITORIES" \
    -o "$NFS_OPTIONS_WRITE" 2>&1 | tee -a "$NFS_LOG"; then
    success "Mounted repositories"
    ((mounted++))
  else
    error "Failed to mount repositories"
  fi
  
  # Mount config vault (read-only)
  log "Mounting $NAS_HOST:$NAS_CONFIG_VAULT to $LOCAL_CONFIG_VAULT..."
  if mount -t "$NFS_VERSION" "$NAS_IP:$NAS_CONFIG_VAULT" "$LOCAL_CONFIG_VAULT" \
    -o "ro,${NFS_OPTIONS_READ}" 2>&1 | tee -a "$NFS_LOG"; then
    success "Mounted config vault (read-only)"
    ((mounted++))
  else
    warn "Could not mount config vault - continuing"
  fi
  
  # Mount audit logs (read-only)
  log "Mounting $NAS_HOST:$NAS_AUDIT_LOGS to $LOCAL_AUDIT_LOGS..."
  if mount -t "$NFS_VERSION" "$NAS_IP:$NAS_AUDIT_LOGS" "$LOCAL_AUDIT_LOGS" \
    -o "ro,${NFS_OPTIONS_READ}" 2>&1 | tee -a "$NFS_LOG"; then
    success "Mounted audit logs (read-only)"
    ((mounted++))
  else
    warn "Could not mount audit logs - continuing"
  fi
  
  log "Successfully mounted $mounted NFS shares"
}

# ============================================================================
# CREATE SYMLINKS
# ============================================================================

create_symlinks() {
  log "Creating symlinks to NFS mounts..."
  
  # Symlink for easy access to repositories via /opt/iac-configs-nas
  if [[ -d "$LOCAL_REPOSITORIES" ]]; then
    ln -sfn "$LOCAL_REPOSITORIES/iac" "$LOCAL_LINK_IAC"
    success "Created symlink: $LOCAL_LINK_IAC → $LOCAL_REPOSITORIES/iac"
  fi
  
  success "Symlinks created"
}

# ============================================================================
# CONFIGURE FSTAB
# ============================================================================

configure_fstab() {
  log "Configuring /etc/fstab for persistent mounts..."
  
  # Backup fstab
  cp /etc/fstab "/etc/fstab.backup.$(date +%s)"
  log "Backed up /etc/fstab"
  
  # Remove existing entries for our mounts (if any)
  sed -i "\|$LOCAL_REPOSITORIES|d" /etc/fstab
  sed -i "\|$LOCAL_CONFIG_VAULT|d" /etc/fstab
  sed -i "\|$LOCAL_AUDIT_LOGS|d" /etc/fstab
  
  # Add NFS mount entries
  cat >> /etc/fstab <<EOF

# NAS NFS Mounts (192.168.168.31 - Dev Node)
# Added: $(date)
${NAS_IP}:${NAS_REPOSITORIES} ${LOCAL_REPOSITORIES} ${NFS_VERSION} ${NFS_OPTIONS_WRITE},x-systemd.automount,x-systemd.mount-timeout=30s 0 0
${NAS_IP}:${NAS_CONFIG_VAULT} ${LOCAL_CONFIG_VAULT} ${NFS_VERSION} ro,${NFS_OPTIONS_READ},x-systemd.automount,x-systemd.mount-timeout=30s 0 0
${NAS_IP}:${NAS_AUDIT_LOGS} ${LOCAL_AUDIT_LOGS} ${NFS_VERSION} ro,${NFS_OPTIONS_READ},x-systemd.automount,x-systemd.mount-timeout=30s 0 0
EOF

  success "Added NFS entries to /etc/fstab"
  log "Mounts will persist across reboots"
}

# ============================================================================
# CREATE SYSTEMD SERVICE FOR MOUNT VALIDATION
# ============================================================================

create_mount_service() {
  log "Creating systemd service for NFS mount validation..."
  
  local service_file="/etc/systemd/system/nas-nfs-mounts.service"
  local mount_script="/opt/automation/scripts/nas-integration/validate-nfs-mounts.sh"
  
  cat > "$service_file" <<'EOF'
[Unit]
Description=NAS NFS Mounts Validation & Repair
Documentation=file:///opt/automation/docs/nas-integration/NAS_NFS_BEST_PRACTICES.md
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/automation/scripts/nas-integration/validate-nfs-mounts.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nas-nfs-mounts
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "$service_file"
  log "Created systemd service: $service_file"
  
  # Create timer for periodic validation
  local timer_file="/etc/systemd/system/nas-nfs-mounts.timer"
  
  cat > "$timer_file" <<'EOF'
[Unit]
Description=NAS NFS Mounts Health Check Timer
Requires=nas-nfs-mounts.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  chmod 644 "$timer_file"
  log "Created systemd timer: $timer_file"
  
  systemctl daemon-reload
  success "Systemd services configured"
}

# ============================================================================
# VALIDATE MOUNTS
# ============================================================================

validate_mounts() {
  log "Validating NFS mounts..."
  
  local valid=0
  local failed=0
  
  # Check repositories mount
  if mountpoint -q "$LOCAL_REPOSITORIES"; then
    success "✓ $LOCAL_REPOSITORIES is mounted"
    ((valid++))
  else
    warn "✗ $LOCAL_REPOSITORIES is NOT mounted"
    ((failed++))
  fi
  
  # Check config vault mount
  if mountpoint -q "$LOCAL_CONFIG_VAULT"; then
    success "✓ $LOCAL_CONFIG_VAULT is mounted"
    ((valid++))
  else
    warn "✗ $LOCAL_CONFIG_VAULT is NOT mounted"
    ((failed++))
  fi
  
  # Check audit logs mount
  if mountpoint -q "$LOCAL_AUDIT_LOGS"; then
    success "✓ $LOCAL_AUDIT_LOGS is mounted"
    ((valid++))
  else
    warn "✗ $LOCAL_AUDIT_LOGS is NOT mounted"
    ((failed++))
  fi
  
  log "Mount validation: $valid mounted, $failed failed"
  
  if [[ $failed -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# SHOW MOUNT STATUS
# ============================================================================

show_mount_status() {
  log "Showing NFS mount status..."
  echo ""
  echo "Mount Status:"
  echo "─────────────────────────────────────────────────"
  mount | grep "$LOCAL_MOUNT_BASE" || echo "No NAS mounts currently active"
  echo ""
  echo "Disk Usage:"
  echo "─────────────────────────────────────────────────"
  df -h | grep "/mnt/nas" || echo "No NAS mount points"
  echo ""
  echo "fstab NFS Entries:"
  echo "─────────────────────────────────────────────────"
  grep "^${NAS_IP}" /etc/fstab || echo "No NFS entries in fstab"
  echo ""
}

# ============================================================================
# UNMOUNT
# ============================================================================

unmount_nfs() {
  log "Unmounting NFS shares..."
  
  # Unmount in reverse order
  for mount_point in "$LOCAL_AUDIT_LOGS" "$LOCAL_CONFIG_VAULT" "$LOCAL_REPOSITORIES"; do
    if mountpoint -q "$mount_point"; then
      log "Unmounting $mount_point..."
      if umount "$mount_point"; then
        success "Unmounted $mount_point"
      else
        warn "Could not unmount $mount_point (may be in use)"
      fi
    fi
  done
  
  success "NFS unmount complete"
}

# ============================================================================
# REMOUNT
# ============================================================================

remount_nfs() {
  log "Remounting NFS shares..."
  
  unmount_nfs
  sleep 2
  mount_nfs
  validate_mounts
  
  success "NFS remount complete"
}

# ============================================================================
# REPAIR MOUNTS
# ============================================================================

repair_mounts() {
  log "Attempting to repair NFS mounts..."
  
  # Kill stale NFS processes
  log "Killing stale NFS processes..."
  pkill -f "nfsd" || true
  pkill -f "lockd" || true
  
  sleep 2
  
  # Remount
  remount_nfs
  
  success "NFS repair complete"
}

# ============================================================================
# ENABLE SERVICES
# ============================================================================

enable_services() {
  log "Enabling NFS mount services..."
  
  systemctl enable nas-nfs-mounts.service
  systemctl enable nas-nfs-mounts.timer
  systemctl start nas-nfs-mounts.timer
  
  success "NFS services enabled and timer started"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local operation="${1:-mount}"
  
  ensure_root
  ensure_log_dir
  
  log "Starting NFS mount operation: $operation"
  
  case "$operation" in
    mount)
      check_prerequisites
      validate_nas_exports
      create_mount_points
      mount_nfs
      create_symlinks
      configure_fstab
      create_mount_service
      enable_services
      validate_mounts || error "Mount validation failed"
      show_mount_status
      success "NFS mounting complete"
      ;;
    
    unmount)
      unmount_nfs
      ;;
    
    remount)
      remount_nfs
      show_mount_status
      ;;
    
    validate)
      validate_mounts
      show_mount_status
      ;;
    
    repair)
      repair_mounts
      show_mount_status
      ;;
    
    status)
      show_mount_status
      ;;
    
    *)
      cat <<'USAGE'
Usage: sudo bash setup-nfs-mounts.sh [OPERATION]

Operations:
  mount      - Setup NFS mounts (default)
  unmount    - Unmount all NFS shares
  remount    - Unmount and remount all shares
  validate   - Check if mounts are active
  repair     - Attempt automatic repair
  status     - Show mount status
  help       - Show this help

Examples:
  sudo bash setup-nfs-mounts.sh mount
  sudo bash setup-nfs-mounts.sh validate
  sudo bash setup-nfs-mounts.sh repair

Mount Points:
  /mnt/nas/repositories   - Infrastructure code (read-write)
  /mnt/nas/config-vault   - Configuration vault (read-only)
  /mnt/nas/audit-logs     - Audit trails (read-only)

Symlinks:
  /opt/iac-configs-nas → /mnt/nas/repositories/iac

Configuration:
  - NFS v4.1 with TCP
  - Auto-mount on boot via systemd
  - Persistent mounts in /etc/fstab
  - Health checks every 30 minutes
USAGE
      ;;
  esac
}

main "$@"
