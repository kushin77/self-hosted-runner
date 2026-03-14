#!/bin/bash
#
# DEPLOYMENT PACKAGE PREPARATION SCRIPT
# Prepares deployment files for transfer to worker node
# via USB, network share, or other offline methods
#

set -euo pipefail

readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_step() {
  echo -e "${YELLOW}▶${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# USB DRIVE PREPARATION
# ============================================================================

prepare_usb() {
  print_header "USB DRIVE PREPARATION"

  print_step "Detecting USB drives..."
  
  # List available block devices
  echo ""
  echo "Available USB drives:"
  lsblk -d -o NAME,SIZE,TYPE,HOTPLUG | grep -E 'usb|disk' || \
    ls -la /dev/sd* 2>/dev/null | tail -5
  
  echo ""
  print_info "Enter USB drive path (e.g., /dev/sdb, /dev/sdc):"
  read -p "USB device: " USB_DEVICE
  
  if [ -z "$USB_DEVICE" ]; then
    print_error "No USB device specified"
    return 1
  fi
  
  if [ ! -e "$USB_DEVICE" ]; then
    print_error "Device not found: $USB_DEVICE"
    return 1
  fi
  
  print_info "USB device: $USB_DEVICE"
  print_info "Enter mount point (e.g., /mnt/usb):"
  read -p "Mount point: " USB_MOUNT
  
  if [ -z "$USB_MOUNT" ]; then
    USB_MOUNT="/mnt/usb"
  fi
  
  # Create mount point
  print_step "Creating mount point: $USB_MOUNT"
  if [ ! -d "$USB_MOUNT" ]; then
    sudo mkdir -p "$USB_MOUNT" || {
      print_error "Failed to create mount point"
      return 1
    }
  fi
  
  # Check if already mounted
  if mountpoint "$USB_MOUNT" &>/dev/null; then
    print_info "Already mounted on $USB_MOUNT"
  else
    # Mount USB
    print_step "Mounting USB drive..."
    if sudo mount "$USB_DEVICE" "$USB_MOUNT" 2>/dev/null; then
      print_success "USB mounted to $USB_MOUNT"
    else
      # Try with different filesystem
      sudo mount -t vfat "$USB_DEVICE" "$USB_MOUNT" 2>/dev/null || \
        sudo mount -t ntfs "$USB_DEVICE" "$USB_MOUNT" 2>/dev/null || {
        print_error "Failed to mount USB drive"
        return 1
      }
    fi
  fi
  
  # Verify we can write to USB
  if [ ! -w "$USB_MOUNT" ]; then
    print_error "No write permission to $USB_MOUNT"
    sudo chmod 777 "$USB_MOUNT" || true
  fi
  
  print_success "USB drive ready at: $USB_MOUNT"
  echo "USB_MOUNT=$USB_MOUNT" >> /tmp/deploy-env.sh
  return 0
}

# ============================================================================
# DEPLOYMENT PACKAGE CREATION
# ============================================================================

create_deployment_package() {
  local target_dir="${1:-.}"
  
  print_header "CREATING DEPLOYMENT PACKAGE"
  
  print_step "Creating package directory structure..."
  
  local pkg_dir="$target_dir/automation-deployment-$TIMESTAMP"
  mkdir -p "$pkg_dir/deployment"
  mkdir -p "$pkg_dir/scripts"
  
  # Copy deployment scripts
  print_step "Copying deployment scripts..."
  
  [ -f "$SCRIPT_DIR/deploy-standalone.sh" ] && \
    cp "$SCRIPT_DIR/deploy-standalone.sh" "$pkg_dir/deployment/" && \
    chmod +x "$pkg_dir/deployment/deploy-standalone.sh" && \
    print_success "Copied deploy-standalone.sh"
  
  [ -f "$SCRIPT_DIR/WORKER_DEPLOYMENT_README.md" ] && \
    cp "$SCRIPT_DIR/WORKER_DEPLOYMENT_README.md" "$pkg_dir/" && \
    print_success "Copied WORKER_DEPLOYMENT_README.md"
  
  [ -f "$SCRIPT_DIR/WORKER_DEPLOYMENT_TRANSFER_GUIDE.md" ] && \
    cp "$SCRIPT_DIR/WORKER_DEPLOYMENT_TRANSFER_GUIDE.md" "$pkg_dir/" && \
    print_success "Copied WORKER_DEPLOYMENT_TRANSFER_GUIDE.md"
  
  # Copy scripts directory
  if [ -d "$SCRIPT_DIR/scripts" ]; then
    print_step "Copying script modules..."
    cp -r "$SCRIPT_DIR/scripts/" "$pkg_dir/scripts/" 2>/dev/null || print_info "Scripts directory not found or empty"
    chmod -R +x "$pkg_dir/scripts"/*.sh 2>/dev/null || true
    print_success "Scripts copied"
  fi
  
  # Create manifest
  print_step "Creating package manifest..."
  cat > "$pkg_dir/MANIFEST.txt" << 'EOF'
DEPLOYMENT PACKAGE MANIFEST
================================

Contents:
  deployment/
    ├── deploy-standalone.sh          Main deployment script
    └── README.md                     Setup instructions
  scripts/
    ├── k8s-health-checks/            Kubernetes health scripts
    ├── security/                     Security audit scripts
    ├── multi-region/                 Failover scripts
    └── automation/                   Core automation scripts
  MANIFEST.txt                        This file
  checksums.md5                       Integrity verification

Installation:
  1. Extract: tar -xzf automation-deployment-*.tar.gz
  2. Transfer to worker node via USB/network
  3. Execute: bash deployment/deploy-standalone.sh

Verification:
  Use MD5 checksums to verify package integrity:
  cd deployment && md5sum -c checksums.md5

Support:
  See WORKER_DEPLOYMENT_README.md for detailed documentation
  See WORKER_DEPLOYMENT_TRANSFER_GUIDE.md for transfer methods

EOF
  
  print_success "Manifest created"
  
  # Create checksums
  print_step "Generating checksums..."
  (cd "$pkg_dir" && find . -type f ! -name "checksums.md5" | sort | xargs md5sum > checksums.md5)
  print_success "Checksums generated"
  
  # Create archive
  print_step "Creating compressed archive..."
  local archive_name="automation-deployment-${TIMESTAMP}.tar.gz"
  
  if tar -czf "$target_dir/$archive_name" -C "$target_dir" "automation-deployment-$TIMESTAMP" 2>/dev/null; then
    print_success "Archive created: $archive_name"
    local size=$(du -h "$target_dir/$archive_name" | cut -f1)
    print_info "Size: $size"
    print_info "Location: $(readlink -f $target_dir/$archive_name)"
    
    # Save path
    echo "ARCHIVE_PATH=$(readlink -f $target_dir/$archive_name)" >> /tmp/deploy-env.sh
    
    # Cleanup
    rm -rf "$pkg_dir"
    
    return 0
  else
    print_error "Failed to create archive"
    rm -rf "$pkg_dir"
    return 1
  fi
}

# ============================================================================
# TRANSFER TO USB
# ============================================================================

transfer_to_usb() {
  if [ ! -f /tmp/deploy-env.sh ]; then
    print_error "No environment file found"
    return 1
  fi
  
  source /tmp/deploy-env.sh
  
  print_header "TRANSFERRING TO USB"
  
  if [ -z "${USB_MOUNT:-}" ]; then
    print_error "USB not mounted"
    return 1
  fi
  
  if [ -z "${ARCHIVE_PATH:-}" ]; then
    print_error "No archive found"
    return 1
  fi
  
  print_step "Copying archive to USB..."
  if rsync -avx --progress "$ARCHIVE_PATH" "$USB_MOUNT/"; then
    print_success "Archive transferred to USB"
  else
    print_error "Failed to transfer archive"
    return 1
  fi
  
  # Verify
  print_step "Verifying transfer..."
  local local_size=$(stat -f%z "$ARCHIVE_PATH" 2>/dev/null || stat -c%s "$ARCHIVE_PATH")
  local usb_size=$(stat -f%z "$USB_MOUNT/$(basename $ARCHIVE_PATH)" 2>/dev/null || stat -c%s "$USB_MOUNT/$(basename $ARCHIVE_PATH)")
  
  if [ "$local_size" = "$usb_size" ]; then
    print_success "Transfer verified (size match)"
  else
    print_error "Transfer verification failed (size mismatch)"
    print_info "Local: $local_size bytes"
    print_info "USB: $usb_size bytes"
    return 1
  fi
  
  return 0
}

# ============================================================================
# FINAL INSTRUCTIONS
# ============================================================================

print_instructions() {
  print_header "DEPLOYMENT TRANSFER COMPLETE"
  
  cat << 'EOF'

Next Steps:

1. SAFELY EJECT USB
   ────────────────
   On Linux:
     sudo umount /mnt/usb
     sudo eject /dev/sdb  (or your USB device)
   
   On macOS:
     diskutil eject /dev/disk4s1

2. TRANSFER USB TO WORKER NODE
   ────────────────────────────
   • Connect USB to dev-elevatediq (192.168.168.42)
   • Mount USB on worker:
     sudo mkdir -p /media/usb
     sudo mount /dev/sdb1 /media/usb

3. EXECUTE DEPLOYMENT
   ───────────────────
   On dev-elevatediq:
     cd /media/usb
     tar -xzf automation-deployment-*.tar.gz
     cd automation-deployment-*/
     bash deployment/deploy-standalone.sh

4. VERIFY DEPLOYMENT
   ──────────────────
   sudo ls -la /opt/automation/
   sudo tail -f /opt/automation/audit/deployment-*.log

EOF
}

# ============================================================================
# NETWORK SHARE OPTION
# ============================================================================

prepare_network_share() {
  print_header "NETWORK SHARE PREPARATION"
  
  print_info "Available network share types:"
  echo "  1. Samba (SMB) - Windows/Linux compatible"
  echo "  2. NFS - Linux specific"
  echo "  3. Direct copy - Same network"
  echo ""
  
  read -p "Select option (1-3): " share_option
  
  case "$share_option" in
    1)
      print_step "Samba share setup..."
      print_info "Install Samba:"
      echo "  sudo apt install samba samba-client"
      print_info "Add share to /etc/samba/smb.conf:"
      echo "  [automation]"
      echo "    path = /tmp/automation-share"
      echo "    public = yes"
      echo "    writable = yes"
      print_info "Create share directory:"
      echo "  mkdir -p /tmp/automation-share && chmod 777 /tmp/automation-share"
      print_info "Restart Samba:"
      echo "  sudo systemctl restart smbd"
      ;;
    2)
      print_step "NFS share setup..."
      print_info "Install NFS:"
      echo "  sudo apt install nfs-kernel-server"
      print_info "Add to /etc/exports:"
      echo "  /tmp/automation-share 192.168.168.0/24(rw,sync,no_subtree_check)"
      print_info "Create share directory:"
      echo "  mkdir -p /tmp/automation-share && sudo exportfs -a"
      ;;
    3)
      print_step "Direct network copy..."
      print_info "Ensure network connectivity:"
      echo "  ping 192.168.168.42"
      print_info "Enable SSH on target (if available):"
      echo "  ssh automation@192.168.168.42"
      ;;
  esac
}

# ============================================================================
# MAIN MENU
# ============================================================================

show_menu() {
  print_header "DEPLOYMENT PACKAGE PREPARATION"
  
  echo "Select preparation method:"
  echo "  1. Create USB deployment package"
  echo "  2. Create network share package"
  echo "  3. Create both (USB + Network)"
  echo "  4. Dockerfile for containerized deployment"
  echo "  5. Exit"
  echo ""
  
  read -p "Enter choice (1-5): " choice
  
  case "$choice" in
    1)
      print_step "USB DRIVE METHOD"
      prepare_usb && \
      create_deployment_package "/tmp" && \
      transfer_to_usb && \
      print_instructions
      ;;
    2)
      print_step "NETWORK SHARE METHOD"
      prepare_network_share && \
      create_deployment_package "/tmp/automation-share"
      ;;
    3)
      print_step "DUAL METHOD (USB + NETWORK)"
      prepare_usb && \
      create_deployment_package "/tmp" && \
      transfer_to_usb && \
      prepare_network_share && \
      create_deployment_package "/tmp/automation-share"
      ;;
    4)
      print_step "DOCKERFILE METHOD"
      print_info "Building Docker image..."
      if [ -f "$SCRIPT_DIR/Dockerfile.worker-deploy" ]; then
        docker build -f "$SCRIPT_DIR/Dockerfile.worker-deploy" \
          -t worker-deploy:latest "$SCRIPT_DIR"
        print_success "Docker image built"
        echo ""
        echo "Usage on worker node:"
        echo "  docker run --rm -v /opt:/target worker-deploy:latest"
      else
        print_error "Dockerfile.worker-deploy not found"
      fi
      ;;
    5)
      print_success "Exiting"
      exit 0
      ;;
    *)
      print_error "Invalid choice"
      ;;
  esac
}

# ==========================================================================
# MAIN
# ==========================================================================

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║  DEPLOYMENT PACKAGE PREPARATION UTILITY                ║"
  echo "║  Prepare worker node deployment for transfer           ║"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""
  
  show_menu
}

main "$@"
