#!/bin/bash
#
# 🚀 EPHEMERAL NODE BOOTSTRAP
#
# Boot sequence for stateless worker nodes
# Automatically discovers NAS, mounts storage, starts services
# Can restart anytime with zero data loss
#
# Runs on every boot via: /etc/systemd/system-generators/ephemeral-generator
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly NAS_DISCOVERY_TIMEOUT=30
readonly NAS_PRIMARY="192.168.168.39"
readonly NAS_BACKUP_DNS="nas.internal.lan"
readonly NAS_USER="automation"
readonly DATA_MOUNT="/data"
readonly HEALTH_CHECK_PORT=5000
readonly HEALTH_CHECK_PATH="/health"

# ============================================================================
# LOGGING
# ============================================================================

BOOT_LOG="/var/log/ephemeral-boot.log"

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$BOOT_LOG"
}

success() { log "✅ $*"; }
warn() { log "⚠️  $*"; }
error() { log "❌ $*"; }

# ============================================================================
# NAS DISCOVERY
# ============================================================================

discover_nas() {
    log "Discovering NAS server..."
    
    # Try primary IP first
    if ping -c 1 -W 2 "$NAS_PRIMARY" &>/dev/null; then
        success "NAS discovered at: $NAS_PRIMARY"
        echo "$NAS_PRIMARY"
        return 0
    fi
    
    # Try DNS fallback
    if nslookup "$NAS_BACKUP_DNS" &>/dev/null; then
        local nas_ip=$(nslookup "$NAS_BACKUP_DNS" | grep "Address:" | tail -1 | awk '{print $NF}')
        if ping -c 1 -W 2 "$nas_ip" &>/dev/null; then
            success "NAS discovered via DNS: $nas_ip"
            echo "$nas_ip"
            return 0
        fi
    fi
    
    # Check DHCP-provided NAS server
    if [[ -n "${NAS_SERVER_IP:-}" ]]; then
        if ping -c 1 -W 2 "$NAS_SERVER_IP" &>/dev/null; then
            success "NAS discovered via DHCP: $NAS_SERVER_IP"
            echo "$NAS_SERVER_IP"
            return 0
        fi
    fi
    
    error "Could not discover NAS server"
    return 1
}

# ============================================================================
# NFS MOUNTING
# ============================================================================

mount_nfs() {
    local nas_host="$1"
    
    log "Mounting NAS storage from: $nas_host"
    
    # Create mount point
    mkdir -p "$DATA_MOUNT"
    
    # Unmount if already mounted (safe reboot)
    if mount | grep -q "$DATA_MOUNT"; then
        log "Unmounting existing mount..."
        umount -f "$DATA_MOUNT" || true
    fi
    
    # NFS mount options optimized for reliability
    local mount_opts="rw,hard,intr,nolock,vers=4.1,proto=tcp,timeo=600,retrans=3"
    
    if ! mount -t nfs4 -o "$mount_opts" \
        "${nas_host}:/export/storage" "$DATA_MOUNT"; then
        error "Failed to mount NAS storage"
        return 1
    fi
    
    # Verify mount succeeded
    if ! df "$DATA_MOUNT" &>/dev/null; then
        error "NAS mount verification failed"
        return 1
    fi
    
    success "NAS storage mounted at: $DATA_MOUNT"
    return 0
}

# ============================================================================
# CREDENTIAL BOOTSTRAP
# ============================================================================

bootstrap_credentials() {
    log "Fetching credentials from GSM..."
    
    # Load credential manager
    source /opt/automation/infrastructure/secret-manager/credential-manager.sh || {
        error "Failed to load credential manager"
        return 1
    }
    
    # Validate critical credentials
    if ! validate_credentials; then
        error "Critical credentials unavailable"
        return 1
    fi
    
    success "Credentials bootstrapped successfully"
    return 0
}

# ============================================================================
# SERVICE STARTUP
# ============================================================================

start_services() {
    log "Starting systemd services..."
    
    # Enable and start essential services
    local services=(
        "docker.service"
        "kubelet.service"
        "kube-proxy.service"
        "containerd.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            log "Starting: $service"
            if systemctl start "$service"; then
                success "Started: $service"
            else
                warn "Failed to start: $service (may retry)"
            fi
        fi
    done
    
    log "Services startup sequence completed"
    return 0
}

# ============================================================================
# HEALTH VERIFICATION
# ============================================================================

health_check() {
    log "Running post-boot health checks..."
    
    local start_time=$(date +%s)
    local timeout=60
    
    while true; do
        local elapsed=$(($(date +%s) - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            warn "Health check timeout after ${timeout}s"
            return 1
        fi
        
        # Check NAS mount
        if ! df "$DATA_MOUNT" &>/dev/null; then
            log "Waiting for NAS mount..."
            sleep 2
            continue
        fi
        
        # Check API endpoint
        if command -v curl &>/dev/null; then
            local http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                "http://localhost:${HEALTH_CHECK_PORT}${HEALTH_CHECK_PATH}" 2>/dev/null || echo "000")
            
            if [[ "$http_code" == "200" ]]; then
                success "All health checks passed"
                return 0
            fi
        fi
        
        log "Health check in progress... (${elapsed}s)"
        sleep 3
    done
    
    return 1
}

# ============================================================================
# AUDIT TRAIL
# ============================================================================

record_boot_event() {
    local event="$1"
    local status="$2"
    
    local audit_file="/data/audit/boots.jsonl"
    mkdir -p "$(dirname "$audit_file")"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local json=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "event": "$event",
  "status": "$status",
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "uptime": "$(uptime -p || echo 'unknown')"
}
EOF
)
    echo "$json" >> "$audit_file"
}

# ============================================================================
# ORCHESTRATION
# ============================================================================

main() {
    log "================================"
    log "EPHEMERAL NODE BOOTSTRAP"
    log "Host: $(hostname)"
    log "================================"
    
    record_boot_event "boot_started" "in_progress"
    
    # Discover NAS
    local nas_host=$(discover_nas) || {
        error "NAS discovery failed - boot aborted"
        record_boot_event "boot_failed" "nas_discovery"
        return 1
    }
    
    # Mount NFS storage
    if ! mount_nfs "$nas_host"; then
        error "NFS mount failed - boot aborted"
        record_boot_event "boot_failed" "nfs_mount"
        return 1
    fi
    
    # Bootstrap credentials
    if ! bootstrap_credentials; then
        error "Credential bootstrap failed"
        record_boot_event "boot_warning" "credentials"
        # Don't abort - some services may start without credentials
    fi
    
    # Start services
    if ! start_services; then
        warn "Some services failed to start"
    fi
    
    # Health check
    if ! health_check; then
        warn "Post-boot health checks incomplete (will continue monitoring)"
    fi
    
    success "EPHEMERAL NODE BOOTSTRAP COMPLETE"
    record_boot_event "boot_complete" "success"
    
    # Install periodic health check
    cat > /etc/cron.d/node-health-check << 'EOF'
# Node health monitoring
*/5 * * * * root /opt/automation/infrastructure/healthcheck-node.sh >> /var/log/node-health.log 2>&1
EOF
    
    return 0
}

# ============================================================================
# EXECUTION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi
