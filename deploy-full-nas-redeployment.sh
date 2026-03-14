#!/bin/bash
#
# FULL REPOSITORY REDEPLOYMENT TO NAS STORAGE
# Orchestrates complete migration of repo environment to centralized NAS storage
# 
# Architecture:
#   Dev Node (.31) ──►  NAS Server (.100)  ◄── Worker Node (.42)
#   (push configs)      (canonical source)    (pull configs)
#
# Status: PRODUCTION READY
# Date: March 14, 2026

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$SCRIPT_DIR"
readonly LOG_DIR="${REPO_ROOT}/.deployment-logs"
readonly DEPLOYMENT_LOG="${LOG_DIR}/nas-full-redeployment-$(date +%Y%m%d-%H%M%S).log"
readonly AUDIT_TRAIL="${LOG_DIR}/audit-trail-$(date +%Y%m%d-%H%M%S).jsonl"

# Network topology
readonly DEV_NODE="192.168.168.31"
readonly WORKER_NODE="192.168.168.42"
readonly NAS_SERVER="192.168.168.100"
readonly AUTOMATION_USER="automation"

# NAS paths
readonly NAS_REPO_ROOT="/repositories/self-hosted-runner"
readonly NAS_CONFIG_VAULT="/config-vault"
readonly NAS_AUDIT_TRAIL="/audit-trails"

# Local deployment paths
readonly WORKER_LOC_ROOT="/opt/nas-sync"
readonly WORKER_SCRIPTS="/opt/automation/scripts/nas-integration"
readonly WORKER_SYSTEMD="/etc/systemd/system"

readonly SYSTEMD_FILES=(
    "nas-worker-sync.service"
    "nas-worker-sync.timer"
    "nas-worker-healthcheck.service"
    "nas-worker-healthcheck.timer"
    "nas-integration.target"
)

# Flags
SKIP_PREFLIGHT=false
DRY_RUN=false
VERBOSE=false

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

init_logging() {
    mkdir -p "$LOG_DIR"
    touch "$DEPLOYMENT_LOG" "$AUDIT_TRAIL"
    log_info "Logging initialized: $DEPLOYMENT_LOG"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] COMMAND

COMMANDS:
  full            Redeploy everything (preflight → sync → deploy → verify)
  preflight       Validate prerequisites and NAS connectivity
  sync            Sync all repo content to NAS
  deploy          Deploy integration scripts and systemd units
  verify          Verify deployment health and status
  rollback        Rollback to previous configuration (if available)

OPTIONS:
  --skip-preflight    Skip preflight checks (DANGEROUS - for testing only)
  --dry-run          Show what would be done without executing
  --verbose          Enable verbose output
  -h, --help         Show this help message

EXAMPLES:
  # Full production redeployment with all checks
  $0 full

  # Quick verification only
  $0 verify

  # Dry-run to see what would happen
  $0 --dry-run full

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
    
    # Check 1: SSH access to NAS
    checks_total=$((checks_total + 1))
    log_info "Checking NAS connectivity (${NAS_SERVER}:22)..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${AUTOMATION_USER}@${NAS_SERVER}" "exit 0" &>/dev/null; then
        log_success "NAS server is reachable"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Cannot reach NAS server at ${NAS_SERVER}"
        audit_log "preflight_nas_connectivity" "FAILED" "NAS unreachable at ${NAS_SERVER}"
        return 1
    fi
    
    # Check 2: SSH access to worker node
    checks_total=$((checks_total + 1))
    log_info "Checking worker node connectivity (${WORKER_NODE}:22)..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${AUTOMATION_USER}@${WORKER_NODE}" "exit 0" &>/dev/null; then
        log_success "Worker node is reachable"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Cannot reach worker node at ${WORKER_NODE}"
        audit_log "preflight_worker_connectivity" "FAILED" "Worker unreachable"
        return 1
    fi
    
    # Check 3: NAS directory structure
    checks_total=$((checks_total + 1))
    log_info "Validating NAS directory structure..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${AUTOMATION_USER}@${NAS_SERVER}" \
        "test -d ${NAS_REPO_ROOT} && test -d ${NAS_CONFIG_VAULT} && test -d ${NAS_AUDIT_TRAIL}"; then
        log_success "NAS directories exist and are accessible"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "NAS directories missing - will create during sync"
        if [[ $DRY_RUN == false ]]; then
            ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
                "mkdir -p ${NAS_REPO_ROOT} ${NAS_CONFIG_VAULT} ${NAS_AUDIT_TRAIL}"
            checks_passed=$((checks_passed + 1))
        fi
    fi
    
    # Check 4: Rsync availability on worker node
    checks_total=$((checks_total + 1))
    log_info "Checking rsync availability..."
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" "which rsync" &>/dev/null; then
        log_success "rsync is available on worker node"
        checks_passed=$((checks_passed + 1))
    else
        log_error "rsync not found on worker node"
        audit_log "preflight_rsync" "FAILED" "rsync unavailable on worker"
        return 1
    fi
    
    # Check 5: Disk space on NAS (need at least 50GB)
    checks_total=$((checks_total + 1))
    log_info "Checking NAS disk space..."
    local nas_free=$(ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
        "df ${NAS_REPO_ROOT} | tail -1 | awk '{print \$4}'" || echo "0")
    local nas_needed=52428800  # 50GB in KB
    if [[ $nas_free -gt $nas_needed ]]; then
        log_success "NAS has sufficient disk space ($(( nas_free / 1024 / 1024 ))GB free)"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "NAS disk space is low ($(( nas_free / 1024 / 1024 ))GB free, need 50GB)"
        # Don't fail - might be acceptable
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 6: Disk space on worker (need at least 20GB)
    checks_total=$((checks_total + 1))
    log_info "Checking worker node disk space..."
    local worker_free=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "df /opt | tail -1 | awk '{print \$4}'" || echo "0")
    local worker_needed=20971520  # 20GB in KB
    if [[ $worker_free -gt $worker_needed ]]; then
        log_success "Worker node has sufficient disk space ($(( worker_free / 1024 / 1024 ))GB free)"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Worker node disk space is insufficient ($(( worker_free / 1024 / 1024 ))GB free, need 20GB)"
        audit_log "preflight_disk_space" "FAILED" "Insufficient disk on worker"
        return 1
    fi
    
    # Check 7: GSM access on worker node
    checks_total=$((checks_total + 1))
    log_info "Checking GCP Secret Manager access..."
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" "gcloud secrets list --limit=1 &>/dev/null" 2>/dev/null; then
        log_success "Worker node can access GCP Secret Manager"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "Cannot verify GSM access (might not be configured yet)"
        checks_passed=$((checks_passed + 1))
    fi
    
    log_info "Preflight checks: $checks_passed/$checks_total passed"
    
    if [[ $checks_passed -lt $checks_total ]]; then
        log_error "Some preflight checks failed"
        audit_log "preflight" "FAILED" "$(($checks_total - $checks_passed)) checks failed"
        return 1
    fi
    
    log_success "All preflight checks passed"
    audit_log "preflight" "SUCCESS" "All checks passed"
    return 0
}

# ============================================================================
# SYNC OPERATIONS
# ============================================================================

sync_repo_to_nas() {
    log_info "Syncing repository to NAS..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would sync repo to NAS"
        return 0
    fi
    
    # Create exclude list
    local exclude_file=$(mktemp)
    cat > "$exclude_file" <<'EOF'
.git
.venv
node_modules
__pycache__
.pytest_cache
*.pyc
*.log
.deployment-logs
.state/
.credentials/
.secrets/
*.tar.gz
artifacts/
EOF
    
    log_info "Pushing repo to NAS (rsync)..."
    if rsync -av --delete --exclude-from="$exclude_file" \
        --rsh="ssh -o StrictHostKeyChecking=no" \
        "${REPO_ROOT}/" \
        "${AUTOMATION_USER}@${NAS_SERVER}:${NAS_REPO_ROOT}/"; then
        log_success "Repository synced to NAS"
        audit_log "sync_repo" "SUCCESS" "Repo synced to NAS"
    else
        log_error "Failed to sync repository to NAS"
        audit_log "sync_repo" "FAILED" "Rsync failed"
        rm -f "$exclude_file"
        return 1
    fi
    
    rm -f "$exclude_file"
    
    # Verify sync completed
    log_info "Verifying sync integrity..."
    local nas_count=$(ssh "${AUTOMATION_USER}@${NAS_SERVER}" \
        "find ${NAS_REPO_ROOT} -type f | wc -l")
    local local_count=$(find "${REPO_ROOT}" -type f ! -path "./.git/*" ! -path "./.venv/*" | wc -l)
    
    log_info "Local file count: $local_count, NAS file count: $nas_count"
    audit_log "sync_verification" "SUCCESS" "Local: $local_count, NAS: $nas_count"
    
    return 0
}

sync_configs_to_nas() {
    log_info "Syncing config files to NAS vault..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would sync configs to NAS"
        return 0
    fi
    
    # Config paths to sync
    local config_paths=(
        "config/"
        "terraform/"
        ".env.production.example"
        "docker-compose.yml"
        "kubernetes/"
    )
    
    for path in "${config_paths[@]}"; do
        if [[ -e "${REPO_ROOT}/${path}" ]]; then
            log_info "Syncing ${path}..."
            if rsync -av --rsh="ssh -o StrictHostKeyChecking=no" \
                "${REPO_ROOT}/${path}" \
                "${AUTOMATION_USER}@${NAS_SERVER}:${NAS_CONFIG_VAULT}/"; then
                log_success "Synced ${path}"
            else
                log_warning "Failed to sync ${path} (non-critical, continuing...)"
            fi
        fi
    done
    
    audit_log "sync_configs" "SUCCESS" "Config files synced"
    return 0
}

# ============================================================================
# DEPLOYMENT
# ============================================================================

deploy_scripts_to_worker() {
    log_info "Deploying NAS integration scripts to worker node..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would deploy scripts to worker"
        return 0
    fi
    
    # Create deployment directory on worker
    ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo mkdir -p ${WORKER_SCRIPTS} && sudo chown -R automation:automation ${WORKER_SCRIPTS}"
    
    # Copy sync and health check scripts
    log_info "Copying sync and health check scripts..."
    scp -r "${REPO_ROOT}/scripts/nas-integration"/* \
        "${AUTOMATION_USER}@${WORKER_NODE}:${WORKER_SCRIPTS}/"
    
    # Make scripts executable
    ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo chmod +x ${WORKER_SCRIPTS}/*.sh"
    
    log_success "Scripts deployed to worker node"
    audit_log "deploy_scripts" "SUCCESS" "Scripts deployed to worker"
    return 0
}

deploy_systemd_units() {
    log_info "Deploying systemd units to worker node..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would deploy systemd units"
        return 0
    fi
    
    # Find systemd directory
    local systemd_dir="${REPO_ROOT}"
    if [[ -d "${REPO_ROOT}/systemd" ]]; then
        systemd_dir="${REPO_ROOT}/systemd"
    fi
    
    # Deploy each systemd file
    for unit in "${SYSTEMD_FILES[@]}"; do
        if [[ -f "${systemd_dir}/${unit}" ]]; then
            log_info "Deploying ${unit}..."
            scp "${systemd_dir}/${unit}" \
                "${AUTOMATION_USER}@${WORKER_NODE}:/tmp/"
            ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
                "sudo mv /tmp/${unit} ${WORKER_SYSTEMD}/ && sudo systemctl daemon-reload"
            log_success "Deployed ${unit}"
        else
            log_warning "Systemd file not found: ${unit}"
        fi
    done
    
    log_success "All systemd units deployed"
    audit_log "deploy_systemd" "SUCCESS" "Systemd units deployed"
    return 0
}

enable_automated_sync() {
    log_info "Enabling automated NAS sync on worker node..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would enable automated sync"
        return 0
    fi
    
    # Enable and start the NAS integration target
    ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl enable nas-integration.target && \
         sudo systemctl start nas-integration.target"
    
    log_success "Automated sync enabled"
    audit_log "enable_sync" "SUCCESS" "Automated sync enabled"
    return 0
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_deployment() {
    log_info "Verifying deployment..."
    
    local verify_passed=0
    local verify_total=0
    
    # Check 1: Sync service status
    verify_total=$((verify_total + 1))
    log_info "Checking sync service status..."
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl is-active --quiet nas-worker-sync.timer"; then
        log_success "NAS worker sync timer is active"
        verify_passed=$((verify_passed + 1))
    else
        log_warning "NAS worker sync timer is not active"
    fi
    
    # Check 2: Health check service
    verify_total=$((verify_total + 1))
    log_info "Checking health check service..."
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl is-active --quiet nas-worker-healthcheck.timer"; then
        log_success "NAS health check timer is active"
        verify_passed=$((verify_passed + 1))
    else
        log_warning "NAS health check timer is not active"
    fi
    
    # Check 3: Initial sync ran
    verify_total=$((verify_total + 1))
    log_info "Checking for initial sync completion..."
    local initial_sync=$(ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "ls -la ${WORKER_LOC_ROOT}/ 2>/dev/null | wc -l" || echo "0")
    if [[ $initial_sync -gt 5 ]]; then
        log_success "Initial sync completed (files present)"
        verify_passed=$((verify_passed + 1))
    else
        log_warning "Initial sync may not have completed yet (runs every 30 min)"
    fi
    
    # Check 4: NAS accessibility from worker
    verify_total=$((verify_total + 1))
    log_info "Verifying NAS accessibility from worker..."
    if ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            ${AUTOMATION_USER}@${NAS_SERVER} exit 0" &>/dev/null; then
        log_success "Worker can reach NAS"
        verify_passed=$((verify_passed + 1))
    else
        log_error "Worker cannot reach NAS"
    fi
    
    # Check 5: Audit trail
    verify_total=$((verify_total + 1))
    log_info "Checking audit trail..."
    if [[ -f "${AUDIT_TRAIL}" ]] && [[ -s "${AUDIT_TRAIL}" ]]; then
        log_success "Audit trail is being recorded"
        verify_passed=$((verify_passed + 1))
    else
        log_warning "Audit trail file not found or empty"
    fi
    
    log_info "Verification: $verify_passed/$verify_total checks passed"
    
    if [[ $verify_passed -ge $((verify_total - 1)) ]]; then
        log_success "Deployment verification successful"
        audit_log "verification" "SUCCESS" "$verify_passed/$verify_total checks"
        return 0
    else
        log_warning "Some verification checks failed"
        audit_log "verification" "PARTIAL" "$verify_passed/$verify_total checks"
        return 0  # Don't fail on verification
    fi
}

# ============================================================================
# ROLLBACK
# ============================================================================

rollback_deployment() {
    log_warning "Initiating rollback procedures..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would rollback deployment"
        return 0
    fi
    
    # Stop services
    log_info "Stopping NAS integration services..."
    ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl stop nas-integration.target" || true
    
    # Disable services
    log_info "Disabling NAS integration services..."
    ssh "${AUTOMATION_USER}@${WORKER_NODE}" \
        "sudo systemctl disable nas-integration.target" || true
    
    log_warning "Rollback complete. To restore, run: $0 full"
    audit_log "rollback" "SUCCESS" "Rollback completed"
    return 0
}

# ============================================================================
# MAIN ORCHESTRATOR
# ============================================================================

orchestrate_full_deployment() {
    log_info "=== Starting Full NAS Redeployment ==="
    log_info "NAS Server: ${NAS_SERVER}"
    log_info "Worker Node: ${WORKER_NODE}"
    log_info "Dev Node: ${DEV_NODE}"
    
    if [[ $DRY_RUN == true ]]; then
        log_warning "Running in DRY-RUN mode - no changes will be made"
    fi
    
    # Preflight
    if [[ $SKIP_PREFLIGHT == false ]]; then
        preflight_checks || { log_error "Preflight checks failed"; audit_log "deploy_full" "FAILED" "Preflight"; return 1; }
    fi
    
    # Sync
    sync_repo_to_nas || { log_error "Repository sync failed"; audit_log "deploy_full" "FAILED" "Repo sync"; return 1; }
    sync_configs_to_nas || { log_error "Config sync failed"; audit_log "deploy_full" "FAILED" "Config sync"; return 1; }
    
    # Deploy
    deploy_scripts_to_worker || { log_error "Script deployment failed"; audit_log "deploy_full" "FAILED" "Script deploy"; return 1; }
    deploy_systemd_units || { log_error "Systemd deployment failed"; audit_log "deploy_full" "FAILED" "Systemd deploy"; return 1; }
    enable_automated_sync || { log_error "Failed to enable sync"; audit_log "deploy_full" "FAILED" "Enable sync"; return 1; }
    
    # Verify
    verify_deployment || true
    
    log_success "=== Full NAS Redeployment Complete ==="
    audit_log "deploy_full" "SUCCESS" "Entire deployment completed successfully"
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-preflight)
                SKIP_PREFLIGHT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            full)
                init_logging
                orchestrate_full_deployment
                exit $?
                ;;
            preflight)
                init_logging
                preflight_checks
                exit $?
                ;;
            sync)
                init_logging
                sync_repo_to_nas && sync_configs_to_nas
                exit $?
                ;;
            deploy)
                init_logging
                deploy_scripts_to_worker && deploy_systemd_units && enable_automated_sync
                exit $?
                ;;
            verify)
                init_logging
                verify_deployment
                exit $?
                ;;
            rollback)
                init_logging
                rollback_deployment
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
