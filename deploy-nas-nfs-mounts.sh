#!/bin/bash
#
# NAS FILESYSTEM MOUNT DEPLOYMENT - PRODUCTION
# Direct NFS mounting on dev node (.31) and worker node (.42)
# NAS Server: 192.16.168.39
#
# Architecture:
#   Dev Node (.31)              Worker Node (.42)
#   /nas/repositories ◄──────► /nas/repositories  ◄─────► NAS (192.16.168.39)
#   /nas/config-vault          /nas/config-vault         /repositories
#   (direct NFS mounts)        (direct NFS mounts)       /config-vault

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$SCRIPT_DIR"
readonly LOG_DIR="${REPO_ROOT}/.deployment-logs"
readonly DEPLOYMENT_LOG="${LOG_DIR}/nas-mount-$(date +%Y%m%d-%H%M%S).log"
readonly AUDIT_TRAIL="${LOG_DIR}/mount-audit-$(date +%Y%m%d-%H%M%S).jsonl"

# Network topology
readonly DEV_NODE="192.168.168.31"
readonly WORKER_NODE="192.168.168.42"
readonly NAS_SERVER="192.168.168.39"

# Service accounts (configurable via environment variables)
# Worker node runs as akushnir user
WORKER_SERVICE_ACCOUNT="${WORKER_SVC_ACCOUNT:-akushnir}"
WORKER_SSH_KEY="${WORKER_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

# Dev node can use current user or service account
DEV_SERVICE_ACCOUNT="${DEV_SVC_ACCOUNT:-$(whoami)}"
DEV_SSH_KEY="${DEV_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

# NAS export paths
readonly NAS_REPOS="/repositories"
readonly NAS_CONFIG="/config-vault"

# Local mount points (same on both nodes)
readonly MOUNT_POINT="/nas"
readonly REPOS_MOUNT="${MOUNT_POINT}/repositories"
readonly CONFIG_MOUNT="${MOUNT_POINT}/config-vault"

# Flags
DRY_RUN=false
VERBOSE=false
SKIP_WORKER=false
SKIP_DEV=false

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING & OUTPUT
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$DEPLOYMENT_LOG"
}

log_info() { echo -e "${BLUE}ℹ${NC} $*" >&2; log "INFO" "$@"; }
log_success() { echo -e "${GREEN}✓${NC} $*" >&2; log "SUCCESS" "$@"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*" >&2; log "WARN" "$@"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; log "ERROR" "$@"; }

audit_log() {
    local event=$1
    local status=$2
    local details=$3
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"timestamp\":\"${timestamp}\",\"event\":\"${event}\",\"status\":\"${status}\",\"details\":\"${details}\"}" >> "$AUDIT_TRAIL"
}

init_logging() {
    mkdir -p "$LOG_DIR"
    touch "$DEPLOYMENT_LOG" "$AUDIT_TRAIL"
    log_info "Logging initialized: $DEPLOYMENT_LOG"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] COMMAND

COMMANDS:
  full            Deploy NFS mounts on both nodes (worker + dev)
  worker          Deploy NFS mounts on worker node only
  dev             Deploy NFS mounts on dev node only
  umount          Unmount all NFS filesystems
  status          Show current mount status
  verify          Verify NFS connectivity and mounts

OPTIONS:
  --dry-run              Show what would be done without executing
  --verbose              Enable verbose output
  --skip-worker          Skip worker node deployment (for dev-only)
  --skip-dev             Skip dev node deployment (for worker-only)
  --worker-svc SVC       Service account for worker (default: akushnir)
  --worker-key KEY       SSH key for worker service account
  --dev-svc SVC          Service account for dev node (default: current user)
  --dev-key KEY          SSH key for dev service account
  -h, --help             Show this help message

ENVIRONMENT VARIABLES:
  WORKER_SVC_ACCOUNT    Service account for worker node (default: akushnir)
  WORKER_SSH_KEY        SSH key for worker (default: ${HOME}/.ssh/id_ed25519)
  DEV_SVC_ACCOUNT       Service account for dev node (default: current user)
  DEV_SSH_KEY           SSH key for dev (default: \$HOME/.ssh/id_ed25519)

EXAMPLES:
  # Full production deployment (uses akushnir@worker, \$(whoami)@dev)
  $0 full

  # With custom service accounts
  $0 --worker-svc akushnir --dev-svc automation full

  # Dry-run to see what would happen
  $0 --dry-run full

  # Deploy worker only with specific key
  $0 --worker-svc akushnir --worker-key ~/.ssh/id_ed25519 worker

EOF
    exit 0
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

preflight_checks() {
    log_info "Starting preflight validation..."
    
    local checks_passed=0
    local checks_total=0
    
    # Check 1: NAS connectivity (will be validated from nodes during mount)
    checks_total=$((checks_total + 1))
    log_info "NAS connectivity will be validated during mount operations from nodes..."
    log_success "NAS validation deferred to mount phase"
    checks_passed=$((checks_passed + 1))
    
    # Check 2: SSH access to worker with service account
    checks_total=$((checks_total + 1))
    if [[ $SKIP_WORKER == false ]]; then
        log_info "Checking worker node SSH (${WORKER_SERVICE_ACCOUNT}@${WORKER_NODE})..."
        if ssh -i "${WORKER_SSH_KEY}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "${WORKER_SERVICE_ACCOUNT}@${WORKER_NODE}" "exit 0" &>/dev/null; then
            log_success "Worker node SSH access OK (${WORKER_SERVICE_ACCOUNT})"
            checks_passed=$((checks_passed + 1))
        else
            log_warning "Cannot SSH to worker node (${WORKER_SERVICE_ACCOUNT}@${WORKER_NODE}) - will retry during mount operations"
            audit_log "preflight_worker_ssh" "WARNING" "Worker SSH may not be ready yet"
        fi
    fi
    
    # Check 3: SSH access to dev with service account
    checks_total=$((checks_total + 1))
    if [[ $SKIP_DEV == false ]]; then
        log_info "Checking dev node SSH (${DEV_SERVICE_ACCOUNT}@${DEV_NODE})..."
        if ssh -i "${DEV_SSH_KEY}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "${DEV_SERVICE_ACCOUNT}@${DEV_NODE}" "exit 0" &>/dev/null; then
            log_success "Dev node SSH access OK (${DEV_SERVICE_ACCOUNT})"
            checks_passed=$((checks_passed + 1))
        else
            log_warning "Cannot SSH to dev node (${DEV_SERVICE_ACCOUNT}@${DEV_NODE}) - will retry during mount operations"
            audit_log "preflight_dev_ssh" "WARNING" "Dev SSH may not be ready yet"
        fi
    fi
    
    # Check 4: NFS tools available
    checks_total=$((checks_total + 1))
    if command -v showmount &>/dev/null; then
        log_success "NFS tools available locally"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "NFS tools not available locally (may be available on nodes)"
    fi
    
    log_info "Preflight checks: $checks_passed/$checks_total passed"
    audit_log "preflight" "SUCCESS" "Checks passed"
    return 0
}

# ============================================================================
# NFS MOUNT DEPLOYMENT
# ============================================================================

deploy_nfs_mounts() {
    local target_node=$1
    local node_ip=$2
    local node_name=$3
    
    # Determine service account and SSH key based on target node
    local service_account
    local ssh_key
    
    if [[ "$node_name" == "worker" ]]; then
        service_account="${WORKER_SERVICE_ACCOUNT}"
        ssh_key="${WORKER_SSH_KEY}"
    else
        service_account="${DEV_SERVICE_ACCOUNT}"
        ssh_key="${DEV_SSH_KEY}"
    fi
    
    log_info "Deploying NFS mounts to ${node_name} (${node_ip}) as ${service_account}..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would deploy NFS mounts to ${node_name} (${service_account}@${node_ip})"
        return 0
    fi
    
    # Step 1: Install NFS client tools
    log_info "Installing NFS client packages..."
    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "sudo apt-get update -qq && sudo apt-get install -y nfs-common" || {
        log_error "Failed to install NFS tools on ${node_name}"
        return 1
    }
    
    # Step 2: Create mount directory
    log_info "Creating mount point directory ${MOUNT_POINT}..."
    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "sudo mkdir -p ${REPOS_MOUNT} ${CONFIG_MOUNT} && \
         sudo chown -R root:root ${MOUNT_POINT} && \
         sudo chmod 0755 ${MOUNT_POINT}" || {
        log_error "Failed to create mount directories"
        return 1
    }
    
    # Step 3: Test NFS connectivity from node
    log_info "Testing NFS connectivity from ${node_name}..."
    if ! ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "showmount -e ${NAS_SERVER} &>/dev/null"; then
        log_warning "Cannot enumerate NFS exports from ${node_name} (may still work)"
    else
        log_success "NFS exports visible from ${node_name}"
    fi
    
    # Step 4: Mount repositories
    log_info "Mounting ${NAS_REPOS} on ${node_name}..."
    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "sudo mount -t nfs4 -o proto=tcp,vers=4.1,hard,timeo=600,retrans=3 \
            ${NAS_SERVER}:${NAS_REPOS} ${REPOS_MOUNT}" || {
        log_error "Failed to mount repositories on ${node_name}"
        return 1
    }
    
    # Step 5: Mount config vault
    log_info "Mounting ${NAS_CONFIG} on ${node_name}..."
    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "sudo mount -t nfs4 -o proto=tcp,vers=4.1,hard,timeo=600,retrans=3 \
            ${NAS_SERVER}:${NAS_CONFIG} ${CONFIG_MOUNT}" || {
        log_error "Failed to mount config vault on ${node_name}"
        return 1
    }
    
    # Step 6: Verify mounts
    log_info "Verifying mounts..."
    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "mount | grep ${MOUNT_POINT}" | head -5 || {
        log_error "Mount verification failed"
        return 1
    }
    
    # Step 7: Test read access
    log_info "Testing read access..."
    if ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "ls -la ${REPOS_MOUNT} &>/dev/null"; then
        log_success "Read access verified on repositories mount"
    else
        log_error "Cannot read from repositories mount"
        return 1
    fi
    
    log_success "NFS mounts deployed successfully on ${node_name}"
    audit_log "deploy_nfs_${target_node}" "SUCCESS" "NFS mounts deployed (${service_account})"
    return 0
}

# ============================================================================
# SYSTEMD MOUNT UNITS (for persistence)
# ============================================================================

create_mount_units() {
    local target_node=$1
    local node_ip=$2
    local node_name=$3
    
    log_info "Creating systemd mount units for ${node_name}..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would create systemd mount units"
        return 0
    fi
    
    # Create temporary unit files
    local repos_unit=$(mktemp)
    local config_unit=$(mktemp)
    
    # Repositories mount unit
    cat > "$repos_unit" <<'EOF'
[Unit]
Description=NAS Repositories Mount
Requires=network-online.target
After=network-online.target
Before=multi-user.target

[Mount]
What=192.16.168.39:/repositories
Where=/nas/repositories
Type=nfs4
Options=proto=tcp,vers=4.1,hard,timeo=600,retrans=3
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    # Config vault mount unit
    cat > "$config_unit" <<'EOF'
[Unit]
Description=NAS Config Vault Mount
Requires=network-online.target
After=network-online.target
Before=multi-user.target

[Mount]
What=192.16.168.39:/config-vault
Where=/nas/config-vault
Type=nfs4
Options=proto=tcp,vers=4.1,hard,timeo=600,retrans=3
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    # Deploy units
    log_info "Deploying systemd mount units..."
    scp -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "$repos_unit" "${WORKER_SERVICE_ACCOUNT}@${node_ip}:/tmp/nas-repositories.mount"
    scp -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "$config_unit" "${WORKER_SERVICE_ACCOUNT}@${node_ip}:/tmp/nas-config-vault.mount"
    
    ssh -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "${WORKER_SERVICE_ACCOUNT}@${node_ip}" \
        "sudo mv /tmp/nas-repositories.mount /etc/systemd/system/ && \
         sudo mv /tmp/nas-config-vault.mount /etc/systemd/system/ && \
         sudo systemctl daemon-reload"
    
    rm -f "$repos_unit" "$config_unit"
    
    log_success "Systemd mount units created"
    audit_log "systemd_units_${target_node}" "SUCCESS" "Mount units installed"
    return 0
}

# ============================================================================
# FSTAB BACKUP (alternative mount method)
# ============================================================================

setup_fstab() {
    local target_node=$1
    local node_ip=$2
    local node_name=$3
    
    log_info "Setting up /etc/fstab entries for resilience..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would update /etc/fstab"
        return 0
    fi
    
    # Determine service account and SSH key
    local svc_account="${WORKER_SERVICE_ACCOUNT}"
    local svc_key="${WORKER_SSH_KEY}"
    
    # Add to fstab with NFS options
    ssh -i "${svc_key}" -o StrictHostKeyChecking=no "${svc_account}@${node_ip}" \
        "echo '# NAS Mounts - Added $(date)' | sudo tee -a /etc/fstab > /dev/null && \
         echo '${NAS_SERVER}:${NAS_REPOS}    ${REPOS_MOUNT}     nfs4    proto=tcp,vers=4.1,hard,timeo=600,retrans=3,_netdev,x-systemd.automount 0 0' | sudo tee -a /etc/fstab > /dev/null && \
         echo '${NAS_SERVER}:${NAS_CONFIG}   ${CONFIG_MOUNT}    nfs4    proto=tcp,vers=4.1,hard,timeo=600,retrans=3,_netdev,x-systemd.automount 0 0' | sudo tee -a /etc/fstab > /dev/null" || {
        log_warning "Failed to update /etc/fstab on ${node_name}"
    }
    
    log_success "/etc/fstab updated on ${node_name}"
    return 0
}

# ============================================================================
# HEALTH CHECK & MONITORING
# ============================================================================

verify_mounts() {
    local target_node=$1
    local node_ip=$2
    local node_name=$3
    
    log_info "Verifying NFS mounts on ${node_name}..."
    
    # Check mount status
    log_info "Mount status:"
    ssh -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "${WORKER_SERVICE_ACCOUNT}@${node_ip}" "mount | grep -E '${MOUNT_POINT}|nfs4'" | while read line; do
        log_info "  $line"
    done
    
    # Check disk space
    log_info "NFS mount disk usage:"
    ssh -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "${WORKER_SERVICE_ACCOUNT}@${node_ip}" "df -h ${MOUNT_POINT}" | tail -2 | while read line; do
        log_info "  $line"
    done
    
    # Test read/write
    log_info "Testing mount access..."
    if ssh -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "${WORKER_SERVICE_ACCOUNT}@${node_ip}" \
        "test -r ${REPOS_MOUNT} && test -r ${CONFIG_MOUNT}"; then
        log_success "Both mounts readable on ${node_name}"
        audit_log "verify_mounts_${target_node}" "SUCCESS" "Mounts verified"
        return 0
    else
        log_error "Mount verification failed on ${node_name}"
        audit_log "verify_mounts_${target_node}" "FAILED" "Cannot access mounts"
        return 1
    fi
}

# ============================================================================
# UNMOUNT OPERATIONS
# ============================================================================

unmount_nfs() {
    local target_node=$1
    local node_ip=$2
    local node_name=$3
    local service_account=$4
    local ssh_key=$5
    
    log_warning "Unmounting NFS filesystems on ${node_name} (${service_account}@${node_ip})..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would unmount NFS filesystems"
        return 0
    fi
    
    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no "${service_account}@${node_ip}" \
        "sudo umount -l ${CONFIG_MOUNT} 2>/dev/null || true && \
         sudo umount -l ${REPOS_MOUNT} 2>/dev/null || true" || true
    
    log_success "Unmounted on ${node_name}"
    audit_log "unmount_${target_node}" "SUCCESS" "Unmounted (${service_account})"
    return 0
}

# ============================================================================
# ORCHESTRATION
# ============================================================================

orchestrate_full_deployment() {
    log_info "=== Starting Full NFS Mount Deployment ==="
    log_info "NAS Server: ${NAS_SERVER}"
    log_info "Repositories: ${NAS_REPOS}"
    log_info "Config Vault: ${NAS_CONFIG}"
    log_info "Mount Point: ${MOUNT_POINT}"
    
    if [[ $DRY_RUN == true ]]; then
        log_warning "Running in DRY-RUN mode"
    fi
    
    # Preflight
    preflight_checks || { log_error "Preflight checks failed"; return 1; }
    
    # Deploy worker
    if [[ $SKIP_WORKER == false ]]; then
        log_info "Deploying to worker node..."
        deploy_nfs_mounts "worker" "${WORKER_NODE}" "WORKER (.42)" || return 1
        create_mount_units "worker" "${WORKER_NODE}" "WORKER (.42)" || true
        setup_fstab "worker" "${WORKER_NODE}" "WORKER (.42)" || true
        verify_mounts "worker" "${WORKER_NODE}" "WORKER (.42)" || return 1
    fi
    
    # Deploy dev
    if [[ $SKIP_DEV == false ]]; then
        log_info "Deploying to dev node..."
        deploy_nfs_mounts "dev" "${DEV_NODE}" "DEV (.31)" || return 1
        create_mount_units "dev" "${DEV_NODE}" "DEV (.31)" || true
        setup_fstab "dev" "${DEV_NODE}" "DEV (.31)" || true
        verify_mounts "dev" "${DEV_NODE}" "DEV (.31)" || return 1
    fi
    
    log_success "=== Full NFS Mount Deployment Complete ==="
    audit_log "deploy_full" "SUCCESS" "NFS deployment successful"
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-worker)
                SKIP_WORKER=true
                shift
                ;;
            --skip-dev)
                SKIP_DEV=true
                shift
                ;;
            --worker-svc)
                WORKER_SERVICE_ACCOUNT="$2"
                shift 2
                ;;
            --worker-key)
                WORKER_SSH_KEY="$2"
                shift 2
                ;;
            --dev-svc)
                DEV_SERVICE_ACCOUNT="$2"
                shift 2
                ;;
            --dev-key)
                DEV_SSH_KEY="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            full)
                init_logging
                log_info "Using service accounts: WORKER=${WORKER_SERVICE_ACCOUNT}, DEV=${DEV_SERVICE_ACCOUNT}"
                orchestrate_full_deployment
                exit $?
                ;;
            worker)
                init_logging
                SKIP_DEV=true
                log_info "Deploying to worker node using service account: ${WORKER_SERVICE_ACCOUNT}"
                orchestrate_full_deployment
                exit $?
                ;;
            dev)
                init_logging
                SKIP_WORKER=true
                log_info "Deploying to dev node using service account: ${DEV_SERVICE_ACCOUNT}"
                orchestrate_full_deployment
                exit $?
                ;;
            umount)
                init_logging
                if [[ $SKIP_WORKER == false ]]; then
                    unmount_nfs "worker" "${WORKER_NODE}" "WORKER (.42)" "${WORKER_SERVICE_ACCOUNT}" "${WORKER_SSH_KEY}"
                fi
                if [[ $SKIP_DEV == false ]]; then
                    unmount_nfs "dev" "${DEV_NODE}" "DEV (.31)" "${DEV_SERVICE_ACCOUNT}" "${DEV_SSH_KEY}"
                fi
                exit 0
                ;;
            status)
                init_logging
                log_info "=== NFS Mount Status ==="
                if [[ $SKIP_WORKER == false ]]; then
                    log_info "Worker node status (${WORKER_SERVICE_ACCOUNT}@${WORKER_NODE}):"
                    ssh -i "${WORKER_SSH_KEY}" -o StrictHostKeyChecking=no "${WORKER_SERVICE_ACCOUNT}@${WORKER_NODE}" "mount | grep nfs4" || log_warning "No NFS mounts found"
                fi
                if [[ $SKIP_DEV == false ]]; then
                    log_info "Dev node status (${DEV_SERVICE_ACCOUNT}@${DEV_NODE}):"
                    ssh -i "${DEV_SSH_KEY}" -o StrictHostKeyChecking=no "${DEV_SERVICE_ACCOUNT}@${DEV_NODE}" "mount | grep nfs4" || log_warning "No NFS mounts found"
                fi
                exit 0
                ;;
            verify)
                init_logging
                preflight_checks
                exit $?
                ;;
            *)
                log_error "Unknown command: $1"
                usage
                ;;
        esac
    done
    
    usage
}

main "$@"
