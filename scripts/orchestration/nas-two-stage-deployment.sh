#!/bin/bash
################################################################################
# 🎯 NAS TWO-STAGE DEPLOYMENT
# 
# Stage 1: NAS Admin (kushin77@192.168.168.39) - Configure exports
# Stage 2: Dev Node (akushnir@192.168.168.31) - Mount and validate
#
# This allows deployment even when SSH key auth isn't fully established
################################################################################

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}❌${NC} $*" >&2; exit 1; }

# ============================================================================
# STAGE 1: NAS CONFIGURATION (Run on NAS as kushin77)
# ============================================================================

stage1_nas_config() {
  log "╔════════════════════════════════════════════════════════════╗"
  log "║    STAGE 1: NAS Configuration (192.168.168.39)              ║"
  log "║    ⚠ Run this on NAS as kushin77@192.168.168.39             ║"
  log "╚════════════════════════════════════════════════════════════╝"
  log ""
  
  cat <<'NASSCRIPT'
#!/bin/bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         NAS EXPORT CONFIGURATION                            ║"
echo "║         Host: 192.168.168.39 (kushin77)                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create directories
echo "Step 1: Creating export directories..."
sudo mkdir -p /export/{repositories,config-vault,audit-logs}
sudo chmod 755 /export /export/{repositories,config-vault,audit-logs}
echo "✓ Directories created"
echo ""

# Step 2: Backup
echo "Step 2: Backing up /etc/exports..."
BACKUP_FILE="/etc/exports.backup.$(date +%Y%m%d-%H%M%S)"
sudo cp /etc/exports "$BACKUP_FILE"
echo "✓ Backup: $BACKUP_FILE"
echo ""

# Step 3: Add NFS exports
echo "Step 3: Adding NFS export entries..."
echo "Appending to /etc/exports:"
sudo tee -a /etc/exports > /dev/null << 'EXPORTS'

# NFS Exports for Dev/Worker Nodes (Added 2026-03-15)
/export/repositories 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/repositories 192.168.168.42(ro,sync,no_subtree_check,root_squash)
/export/config-vault 192.168.168.31(ro,sync,no_subtree_check,root_squash)
/export/config-vault 192.168.168.42(ro,sync,no_subtree_check,root_squash)
/export/audit-logs 192.168.168.31(ro,sync,no_subtree_check,root_squash)
/export/audit-logs 192.168.168.42(ro,sync,no_subtree_check,root_squash)
EXPORTS
echo "✓ Entries added"
echo ""

# Step 4: Export shares
echo "Step 4: Exporting NFS shares..."
sudo exportfs -r
echo "✓ Exports reloaded"
echo ""

# Step 5: Verify
echo "Step 5: Verifying configuration..."
echo "Current NFS exports:"
sudo showmount -e localhost
echo ""
echo "✓ STAGE 1 COMPLETE"
NASSCRIPT
}

# ============================================================================
# STAGE 2: DEV NODE CONFIGURATION (Run on dev node 192.168.168.31)
# ============================================================================

stage2_devnode_config() {
  log ""
  log "╔════════════════════════════════════════════════════════════╗"
  log "║    STAGE 2: Dev Node Configuration (192.168.168.31)         ║"
  log "║    ⚠ Run this on Dev Node as akushnir@192.168.168.31        ║"
  log "╚════════════════════════════════════════════════════════════╝"
  log ""
  
  cat <<'DEVSCRIPT'
#!/bin/bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         DEV NODE NFS MOUNT SETUP                            ║"
echo "║         Host: 192.168.168.31 (akushnir)                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create mount directories
echo "Step 1: Creating mount directories..."
sudo mkdir -p /mnt/nas/{repositories,config-vault,audit-logs}
echo "✓ Mount directories created"
echo ""

# Step 2: NFS mount options
echo "Step 2: Setting NFS mount options..."
NFS_OPTS_BASE="vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576"
NFS_OPTS_RW="${NFS_OPTS_BASE}"
NFS_OPTS_RO="${NFS_OPTS_BASE},ro"
echo "✓ Mount options configured"
echo ""

# Step 3: Mount repositories (RW)
echo "Step 3: Mounting repositories (RW)..."
if ! mountpoint -q /mnt/nas/repositories 2>/dev/null; then
  sudo mount -t nfs4 -o "${NFS_OPTS_RW}" 192.168.168.39:/export/repositories /mnt/nas/repositories
  echo "✓ Repositories mounted"
else
  echo "ℹ Repositories already mounted"
fi
echo ""

# Step 4: Mount config-vault (RO)
echo "Step 4: Mounting config-vault (RO)..."
if ! mountpoint -q /mnt/nas/config-vault 2>/dev/null; then
  sudo mount -t nfs4 -o "${NFS_OPTS_RO}" 192.168.168.39:/export/config-vault /mnt/nas/config-vault
  echo "✓ Config vault mounted"
else
  echo "ℹ Config vault already mounted"
fi
echo ""

# Step 5: Mount audit-logs (RO)
echo "Step 5: Mounting audit-logs (RO)..."
if ! mountpoint -q /mnt/nas/audit-logs 2>/dev/null; then
  sudo mount -t nfs4 -o "${NFS_OPTS_RO}" 192.168.168.39:/export/audit-logs /mnt/nas/audit-logs
  echo "✓ Audit logs mounted"
else
  echo "ℹ Audit logs already mounted"
fi
echo ""

# Step 6: Persist in fstab
echo "Step 6: Persisting mounts in /etc/fstab..."
if ! grep -q "192.168.168.39:/export" /etc/fstab 2>/dev/null; then
  sudo tee -a /etc/fstab > /dev/null << 'FSTAB'

# NAS Mounts (Added 2026-03-15 via NAS Direct Deployment)
192.168.168.39:/export/repositories /mnt/nas/repositories nfs4 vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576 0 0
192.168.168.39:/export/config-vault /mnt/nas/config-vault nfs4 vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,ro 0 0
192.168.168.39:/export/audit-logs /mnt/nas/audit-logs nfs4 vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,ro 0 0
FSTAB
  echo "✓ Mounts persisted to fstab"
else
  echo "ℹ fstab already contains NAS mounts"
fi
echo ""

# Step 7: Setup health check service
echo "Step 7: Setting up NAS health check service..."
sudo tee /etc/systemd/system/nas-health-check.service > /dev/null << 'SERVICE'
[Unit]
Description=NAS Health Check Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nas-health-check.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

sudo tee /etc/systemd/system/nas-health-check.timer > /dev/null << 'TIMER'
[Unit]
Description=NAS Health Check Timer
Requires=nas-health-check.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# Create health check script
sudo tee /usr/local/bin/nas-health-check.sh > /dev/null << 'SCRIPT'
#!/bin/bash
set -euo pipefail

MOUNT_POINTS=("/mnt/nas/repositories" "/mnt/nas/config-vault" "/mnt/nas/audit-logs")
LOG_FILE="/var/log/nas-health-check.log"

{
  echo "[$(date -Iseconds)] NAS Health Check"
  
  for mount in "${MOUNT_POINTS[@]}"; do
    if mountpoint -q "$mount" 2>/dev/null; then
      echo "✓ $mount: OK (mounted)"
    else
      echo "✗ $mount: FAILED (not mounted)"
      # Attempt remount
      mount -a || echo "✗ Auto-remount failed"
    fi
  done
  
  echo "---"
} >> "$LOG_FILE"
SCRIPT

sudo chmod +x /usr/local/bin/nas-health-check.sh
echo "✓ Health check service created"
echo ""

# Step 8: Enable systemd services
echo "Step 8: Enabling systemd services..."
sudo systemctl daemon-reload
sudo systemctl enable nas-health-check.timer
sudo systemctl start nas-health-check.timer
echo "✓ Services enabled and started"
echo ""

# Step 9: Verify mounts
echo "Step 9: Verifying all mounts..."
df -h /mnt/nas/{repositories,config-vault,audit-logs} || echo "ℹ One or more mounts may not be visible yet"
echo ""

# Step 10: System status
echo "Step 10: System status..."
echo "NFS Protocol Versions:"
mount | grep "/mnt/nas" | grep -o "vers=[0-9.]*" || echo "ℹ Mount info not available"
echo ""
echo "✓ STAGE 2 COMPLETE"
echo ""
echo "Next steps:"
echo "  1. Monitor: sudo systemctl status nas-health-check.timer"
echo "  2. Logs: journalctl -u nas-health-check.service -f"
echo "  3. Test: ls -la /mnt/nas/repositories"
echo "  4. Verify: df -h /mnt/nas/*"
DEVSCRIPT
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local stage="${1:-both}"
  
  case "$stage" in
    stage1)
      stage1_nas_config
      ;;
    stage2)
      stage2_devnode_config
      ;;
    both|all)
      stage1_nas_config
      stage2_devnode_config
      ;;
    *)
      error "Usage: $0 {stage1|stage2|both}"
      ;;
  esac
}

main "$@"
