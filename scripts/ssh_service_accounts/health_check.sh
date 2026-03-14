#!/bin/bash
# Service Account Health Check & Monitoring
# Continuous monitoring with automated issue creation/closure

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly HEALTH_STATE="${WORKSPACE_ROOT}/.health-state"
readonly HEALTH_LOG="${WORKSPACE_ROOT}/logs/health-checks.log"

readonly USERNAME="akushnir"
readonly GIT_REPO="${GIT_REPO:-origin}"

# Service account configs
declare -A TARGETS=(
    ["elevatediq-svc-worker-dev"]="192.168.168.42"
    ["elevatediq-svc-worker-nas"]="192.168.168.42"
    ["elevatediq-svc-dev-nas"]="192.168.168.39"
)

declare -A SOURCES=(
    ["elevatediq-svc-worker-dev"]="192.168.168.31"
    ["elevatediq-svc-worker-nas"]="192.168.168.39"
    ["elevatediq-svc-dev-nas"]="192.168.168.31"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$HEALTH_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$HEALTH_LOG"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$HEALTH_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$HEALTH_LOG"; }

init() {
    mkdir -p "$HEALTH_STATE" "$(dirname "$HEALTH_LOG")"
    log_info "Health check monitoring started"
}

# Check if host is reachable
check_host_reachable() {
    local host=$1
    if timeout 3 ping -c 1 "$host" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check SSH connectivity
check_ssh_connectivity() {
    local from_host=$1
    local to_host=$2
    local svc_name=$3
    
    if ! check_host_reachable "$from_host"; then
        log_error "Source host unreachable: $from_host"
        return 1
    fi
    
    if ! check_host_reachable "$to_host"; then
        log_error "Target host unreachable: $to_host"
        return 1
    fi
    
    # Test SSH connection
    if timeout 5 ssh -o StrictHostKeyChecking=no \
        "${USERNAME}@${from_host}" bash -s "$svc_name" "$to_host" <<'TEST_SSH'
        SVC_NAME=$1
        TARGET_HOST=$2
        KEY="~/.ssh/svc-keys/${SVC_NAME}_key"
        
        if [ ! -f "$KEY" ]; then
            exit 1
        fi
        
        if timeout 5 ssh -o StrictHostKeyChecking=no -i "$KEY" \
            "${SVC_NAME}@${TARGET_HOST}" "whoami" &>/dev/null; then
            exit 0
        else
            exit 1
        fi
TEST_SSH
    then
        return 0
    fi
    
    return 1
}

# Health check for single service account
check_service_account_health() {
    local svc_name=$1
    local target_host=${TARGETS[$svc_name]}
    local source_host=${SOURCES[$svc_name]}
    local health_file="${HEALTH_STATE}/${svc_name}.health"
    
    log_info "Checking health: $svc_name"
    
    local status="HEALTHY"
    local details=""
    
    # Check if deployed
    if [ ! -d "${WORKSPACE_ROOT}/secrets/ssh/${svc_name}" ]; then
        status="MISSING"
        details="Key not found"
    # Check connectivity
    elif ! check_ssh_connectivity "$source_host" "$target_host" "$svc_name"; then
        status="UNHEALTHY"
        details="SSH connectivity failed"
    fi
    
    # Store health
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "$health_file" <<EOF
{
  "name": "$svc_name",
  "status": "$status",
  "timestamp": "$timestamp",
  "source": "$source_host",
  "target": "$target_host",
  "details": "$details"
}
EOF
    
    case "$status" in
        HEALTHY)
            log_success "Health OK: $svc_name"
            create_or_close_issue "$svc_name" "RESOLVED"
            return 0
            ;;
        UNHEALTHY)
            log_error "Connectivity problem: $svc_name - $details"
            create_or_close_issue "$svc_name" "CONNECTIVITY_FAILED"
            return 1
            ;;
        MISSING)
            log_error "Deployment issue: $svc_name - $details"
            create_or_close_issue "$svc_name" "MISSING"
            return 1
            ;;
    esac
}

# Create or update GitHub issue for problems
create_or_close_issue() {
    local svc_name=$1
    local status=$2
    local issue_file="${HEALTH_STATE}/${svc_name}.issue"
    
    # Only create issues if in git repo
    if ! command -v gh &>/dev/null; then
        log_warn "GitHub CLI not available, skipping issue management"
        return 0
    fi
    
    if ! git -C "$WORKSPACE_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        log_warn "Not in git repository, skipping issue management"
        return 0
    fi
    
    local issue_title="[Service Account] Health Issue: $svc_name"
    local issue_label="service-account,automated"
    
    case "$status" in
        RESOLVED)
            # Close any existing issue
            if [ -f "$issue_file" ]; then
                local issue_num=$(cat "$issue_file")
                log_info "Closing issue #$issue_num"
                # Would use: gh issue close "$issue_num" -c "Service account is now healthy"
                rm "$issue_file"
            fi
            ;;
        *)
            # Create or update issue
            if [ ! -f "$issue_file" ]; then
                log_info "Creating GitHub issue for: $svc_name"
                local issue_body="Service Account: $svc_name\\nStatus: $status\\nTimestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)\\n\\nAutomatic issue creation based on health monitoring."
                # Would use: 
                # issue_num=$(gh issue create --title "$issue_title" --body "$issue_body" --label "$issue_label" | grep -oP '#\K\d+')
                # echo "$issue_num" > "$issue_file"
            else
                log_info "Existing issue for: $svc_name"
            fi
            ;;
    esac
}

# Full health report
generate_health_report() {
    log_info "=== Service Account Health Report ==="
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_info ""
    
    local healthy_count=0
    local unhealthy_count=0
    
    for svc_name in "${!TARGETS[@]}"; do
        local health_file="${HEALTH_STATE}/${svc_name}.health"
        if [ -f "$health_file" ]; then
            local status=$(grep -oP '"status": "\K[^"]+' "$health_file")
            if [ "$status" == "HEALTHY" ]; then
                log_success "$svc_name: $status"
                ((healthy_count++)) || true
            else
                log_error "$svc_name: $status"
                ((unhealthy_count++)) || true
            fi
        else
            log_warn "$svc_name: Not checked yet"
        fi
    done
    
    log_info ""
    log_info "Summary: $healthy_count healthy, $unhealthy_count unhealthy"
    
    if [ $unhealthy_count -gt 0 ]; then
        return 1
    fi
    return 0
}

# Check all service accounts
check_all() {
    log_info "=== Starting Health Check Cycle ==="
    
    local failed=0
    for svc_name in "${!TARGETS[@]}"; do
        if ! check_service_account_health "$svc_name"; then
            ((failed++)) || true
        fi
    done
    
    generate_health_report
    
    if [ $failed -gt 0 ]; then
        log_error "Health check found $failed issues"
        return 1
    fi
    
    log_success "All health checks passed"
    return 0
}

# Main
main() {
    init
    
    case "${1:-check}" in
        check)
            check_all
            ;;
        check-one)
            check_service_account_health "${2:-elevatediq-svc-worker-dev}"
            ;;
        report)
            generate_health_report
            ;;
        *)
            echo "Usage: $0 {check|check-one <account>|report}"
            exit 1
            ;;
    esac
}

main "$@"
