#!/bin/bash
#
# LOCAL NAS NFS MOUNT SETUP
# Execute this script directly on each node (dev .31 or worker .42)
# Does NOT require SSH access from remote orchestration
#
# Usage: sudo bash setup-nas-nfs-local.sh

set -euo pipefail

# Configuration
readonly NAS_SERVER="192.168.168.39"
readonly NAS_REPOS="/repositories"
readonly NAS_CONFIG="/config-vault"
readonly MOUNT_BASE="/nas"
readonly REPOS_MOUNT="${MOUNT_BASE}/repositories"
readonly CONFIG_MOUNT="${MOUNT_BASE}/config-vault"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Functions
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  NAS NFS Mount Setup (Local Node)                     ║${NC}"
    echo -e "${BLUE}║  $(date +%Y-%m-%d\ %H:%M:%S)${BLUE}                                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Step 1: Install NFS tools
    log_info "Step 1: Installing NFS client tools..."
    apt-get update -qq
    apt-get install -y nfs-common >/dev/null 2>&1
    log_success "NFS tools installed"
    
    # Step 2: Create mount directories
    log_info "Step 2: Creating mount point directories..."
    mkdir -p "${REPOS_MOUNT}" "${CONFIG_MOUNT}"
    chown root:root "${MOUNT_BASE}"
    chmod 0755 "${MOUNT_BASE}"
    log_success "Mount directories created at ${MOUNT_BASE}"
    
    # Step 3: Check NFS availability from this node
    log_info "Step 3: Checking NAS availability..."
    if ! showmount -e "${NAS_SERVER}" &>/dev/null; then
        log_warn "Cannot enumerate NAS exports, but will continue (may still work)"
    else
        log_success "NAS server is responding"
    fi
    
    # Step 4: Mount repositories
    log_info "Step 4: Mounting repositories from NAS..."
    if ! mount | grep -q "${REPOS_MOUNT}"; then
        if mount -t nfs4 -o proto=tcp,vers=4.1,hard,timeo=600,retrans=3,rsize=131072,wsize=131072 \
            "${NAS_SERVER}:${NAS_REPOS}" "${REPOS_MOUNT}"; then
            log_success "Repositories mounted successfully"
        else
            log_error "Failed to mount repositories"
            exit 1
        fi
    else
        log_warn "Repositories already mounted"
    fi
    
    # Step 5: Mount config vault
    log_info "Step 5: Mounting config vault from NAS..."
    if ! mount | grep -q "${CONFIG_MOUNT}"; then
        if mount -t nfs4 -o proto=tcp,vers=4.1,hard,timeo=600,retrans=3,rsize=131072,wsize=131072 \
            "${NAS_SERVER}:${NAS_CONFIG}" "${CONFIG_MOUNT}"; then
            log_success "Config vault mounted successfully"
        else
            log_error "Failed to mount config vault"
            exit 1
        fi
    else
        log_warn "Config vault already mounted"
    fi
    
    # Step 6: Verify mounts
    log_info "Step 6: Verifying mount status..."
    echo
    mount | grep nfs4 | grep "${MOUNT_BASE}" || log_warn "No NFS v4 mounts detected"
    echo
    
    # Step 7: Test read access
    log_info "Step 7: Testing read access..."
    if ls -la "${REPOS_MOUNT}" >/dev/null 2>&1; then
        local file_count=$(find "${REPOS_MOUNT}" -type f -maxdepth 3 2>/dev/null | wc -l)
        log_success "Repositories mount readable (${file_count} files found)"
    else
        log_error "Cannot read from repositories mount"
        exit 1
    fi
    
    if ls -la "${CONFIG_MOUNT}" >/dev/null 2>&1; then
        log_success "Config vault mount readable"
    else
        log_error "Cannot read from config vault mount"
        exit 1
    fi
    
    # Step 8: Update /etc/fstab for persistent mounting
    log_info "Step 8: Updating /etc/fstab for persistent mounting..."
    if ! grep -q "${NAS_SERVER}:${NAS_REPOS}" /etc/fstab; then
        {
            echo "# NAS Mounts - Added $(date)"
            echo "${NAS_SERVER}:${NAS_REPOS}    ${REPOS_MOUNT}     nfs4    proto=tcp,vers=4.1,hard,timeo=600,retrans=3,rsize=131072,wsize=131072,_netdev 0 0"
            echo "${NAS_SERVER}:${NAS_CONFIG}   ${CONFIG_MOUNT}    nfs4    proto=tcp,vers=4.1,hard,timeo=600,retrans=3,rsize=131072,wsize=131072,_netdev 0 0"
        } >> /etc/fstab
        log_success "/etc/fstab updated"
    else
        log_warn "/etc/fstab already contains NAS entries"
    fi
    
    # Step 9: Display status
    log_info "Step 9: Final status..."
    echo
    df -h | grep -E "Filesystem|${MOUNT_BASE}" || true
    echo
    
    # Step 10: Show systemd mount units status
    log_info "Step 10: Checking systemd mount units..."
    if systemctl list-units --all | grep -q "nas-repositories.mount"; then
        systemctl status nas-repositories.mount --no-pager || true
    else
        log_warn "Systemd mount units not yet deployed"
    fi
    
    echo
    log_success "═══════════════════════════════════════════════════════════"
    log_success "NAS NFS mounts configured successfully!"
    log_success "✓ Repositories: ${REPOS_MOUNT}"
    log_success "✓ Config Vault: ${CONFIG_MOUNT}"
    log_success "✓ NAS Server: ${NAS_SERVER}"
    log_success "═══════════════════════════════════════════════════════════"
    echo
}

main
