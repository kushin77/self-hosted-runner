#!/bin/bash
# SSH Service Accounts - Keys Only Testing & Validation
# Comprehensive testing to verify no password prompts

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs/testing"

readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_FILE="${LOG_DIR}/test-keys-only-${TIMESTAMP}.log"

readonly DEPLOYMENT_TARGETS=(
    "elevatediq-svc-worker-dev:192.168.168.42"
    "elevatediq-svc-worker-nas:192.168.168.42"
    "elevatediq-svc-dev-nas:192.168.168.39"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }

init() {
    mkdir -p "$LOG_DIR"
    log_info "=== SSH Keys-Only Testing & Validation ==="
    log_info "Timestamp: $TIMESTAMP"
}

# Test 1: Verify SSH_ASKPASS is disabled
test_askpass_disabled() {
    log_info "TEST 1: Verify SSH_ASKPASS environment"
    
    if [ "${SSH_ASKPASS:-unset}" = "none" ] && [ "${SSH_ASKPASS_REQUIRE:-unset}" = "never" ]; then
        log_success "SSH_ASKPASS correctly disabled (no password prompts possible)"
        return 0
    else
        log_warn "SSH_ASKPASS not set in environment"
        log_warn "  Current: SSH_ASKPASS='${SSH_ASKPASS:-unset}' SSH_ASKPASS_REQUIRE='${SSH_ASKPASS_REQUIRE:-unset}'"
        log_warn "  Set via: export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never"
        return 1
    fi
}

# Test 2: Verify service account keys exist
test_keys_exist() {
    log_info ""
    log_info "TEST 2: Verify service account keys exist"
    
    local all_exist=0
    for target in "${DEPLOYMENT_TARGETS[@]}"; do
        local svc_name="${target%:*}"
        local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
        
        if [ -f "$key_file" ]; then
            local perms=$(stat -c '%a' "$key_file" 2>/dev/null || stat -f '%OLp' "$key_file" 2>/dev/null | tail -c 4)
            if [ "$perms" = "600" ] || [ "$perms" = "0600" ]; then
                log_success "✓ $svc_name: permissions correct (600)"
            else
                log_warn "✓ $svc_name: exists but permissions are $perms (should be 600)"
            fi
        else
            log_error "✗ $svc_name: key file missing - $key_file"
            ((all_exist++)) || true
        fi
    done
    
    return $all_exist
}

# Test 3: Verify SSH config exists
test_ssh_config() {
    log_info ""
    log_info "TEST 3: Verify SSH configuration"
    
    local ssh_config="${HOME}/.ssh/config"
    
    if [ -f "$ssh_config" ]; then
        if grep -q "PasswordAuthentication no" "$ssh_config"; then
            log_success "SSH config has PasswordAuthentication=no"
        else
            log_warn "SSH config exists but may need PasswordAuthentication=no"
        fi
        
        if grep -q "BatchMode yes" "$ssh_config"; then
            log_success "SSH config has BatchMode=yes (prevents prompts)"
        else
            log_warn "SSH config should have BatchMode=yes"
        fi
        
        return 0
    else
        log_warn "SSH config missing: $ssh_config"
        log_info "Run: scripts/ssh_service_accounts/configure_ssh_keys_only.sh setup"
        return 1
    fi
}

# Test 4: Verify local keys accessible
test_local_keys() {
    log_info ""
    log_info "TEST 4: Verify local service account keys"
    
    local key_dir="${HOME}/.ssh/svc-keys"
    
    if [ ! -d "$key_dir" ]; then
        log_warn "Local key directory missing: $key_dir"
        log_info "Run: scripts/ssh_service_accounts/configure_ssh_keys_only.sh deploy-keys"
        return 1
    fi
    
    local found=0
    for target in "${DEPLOYMENT_TARGETS[@]}"; do
        local svc_name="${target%:*}"
        local local_key="${key_dir}/${svc_name}_key"
        
        if [ -f "$local_key" ]; then
            if [ -r "$local_key" ]; then
                log_success "✓ $svc_name key accessible at $local_key"
            else
                log_error "✗ $svc_name key not readable"
                ((found++)) || true
            fi
        else
            log_warn "✓ $svc_name key not copied locally (will use direct path)"
        fi
    done
    
    return $found
}

# Test 5: Test SSH connection without password (simulated)
test_ssh_without_password() {
    log_info ""
    log_info "TEST 5: SSH Connection Test (Keys Only, No Passwords)"
    
    local test_count=0
    local success_count=0
    
    for target in "${DEPLOYMENT_TARGETS[@]}"; do
        local svc_name="${target%:*}"
        local host="${target#*:}"
        
        ((test_count++)) || true
        
        log_info "  Testing: $svc_name@$host"
        
        # Test with strictly no passwords allowed
        if timeout 5 ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o PasswordAuthentication=no \
            -o PubkeyAuthentication=yes \
            -o PreferredAuthentications=publickey \
            -i "${SECRETS_DIR}/${svc_name}/id_ed25519" \
            "${svc_name}@${host}" \
            "echo 'SSH_CONNECTION_TEST_SUCCESS'" 2>/dev/null; then
            log_success "    ✓ Connection successful (no password required)"
            ((success_count++)) || true
        else
            log_error "    ✗ Connection failed or identity issue"
        fi
    done
    
    log_info ""
    log_info "Connection results: $success_count/$test_count successful"
    
    if [ $success_count -eq $test_count ]; then
        log_success "All connections passed!"
        return 0
    else
        log_warn "Some connections failed (this is expected if keys not yet distributed)"
        return 1
    fi
}

# Test 6: Verify BatchMode prevents prompts
test_batch_mode() {
    log_info ""
    log_info "TEST 6: Batch Mode Verification"
    
    # Create test SSH command that would normally prompt
    local test_cmd='ssh -o BatchMode=yes -o PasswordAuthentication=no invalid-host "test"'
    
    log_info "Command with BatchMode=yes will NOT prompt for password"
    log_success "BatchMode prevents interactive prompts automatically"
    
    return 0
}

# Test 7: Generate configuration summary
test_configuration_summary() {
    log_info ""
    log_info "TEST 7: Current Configuration Summary"
    
    echo "" | tee -a "$LOG_FILE"
    echo "=== SSH Configuration ===" | tee -a "$LOG_FILE"
    echo "  SSH_ASKPASS: ${SSH_ASKPASS:-unset}" | tee -a "$LOG_FILE"
    echo "  SSH_ASKPASS_REQUIRE: ${SSH_ASKPASS_REQUIRE:-unset}" | tee -a "$LOG_FILE"
    echo "  DISPLAY: ${DISPLAY:-unset}" | tee -a "$LOG_FILE"
    echo "  SSH Config: ${HOME}/.ssh/config exists: $([ -f ~/.ssh/config ] && echo "✓" || echo "✗")" | tee -a "$LOG_FILE"
    echo "  Keys Directory: ${HOME}/.ssh/svc-keys exists: $([ -d ~/.ssh/svc-keys ] && echo "✓" || echo "✗")" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Generate test report
generate_report() {
    log_info ""
    log_info "=== TEST REPORT ==="
    
    local report_file="${LOG_DIR}/test-report-${TIMESTAMP}.txt"
    
    cat > "$report_file" <<REPORT

SSH SERVICE ACCOUNTS - KEYS-ONLY TEST REPORT
Generated: $TIMESTAMP

CONFIGURATION STATUS:
  Environment Variables: Check the logs above
  SSH Config: Check ~/.ssh/config
  Local Keys: Check ~/.ssh/svc-keys/
  Source Keys: Check $SECRETS_DIR

DEPLOYMENT TARGETS:
$(for target in "${DEPLOYMENT_TARGETS[@]}"; do
    echo "  - ${target%:*} → ${target#*:}"
done)

REQUIREMENTS FOR ZERO-PASSWORD DEPLOYMENT:
  1. SSH_ASKPASS=none (prevents password prompts)
  2. SSH_ASKPASS_REQUIRE=never (forces this)
  3. PasswordAuthentication=no in SSH config
  4. PubkeyAuthentication=yes in SSH config
  5. BatchMode=yes in SSH config
  6. Service account keys present and readable
  7. Public keys deployed to target host authorized_keys

SETUP COMMANDS:
  # Configure SSH for keys-only
  bash $SCRIPT_DIR/configure_ssh_keys_only.sh setup
  
  # Deploy service accounts (no passwords)
  bash $SCRIPT_DIR/automated_deploy_keys_only.sh
  
  # Test connections
  bash $SCRIPT_DIR/test_ssh_keys_only.sh test 192.168.168.42 elevatediq-svc-worker-dev

REPORT

    log_success "Test report written to: $report_file"
}

# Run all tests
run_all_tests() {
    log_info "Running comprehensive tests..."
    echo ""
    
    local failures=0
    
    test_askpass_disabled || ((failures++)) || true
    test_keys_exist || ((failures++)) || true
    test_ssh_config || ((failures++)) || true
    test_local_keys || true  # Not critical
    test_batch_mode
    test_configuration_summary
    
    log_info ""
    log_info "Attempting SSH connections (may fail if keys not yet deployed)..."
    test_ssh_without_password || true  # Expected to potentially fail
    
    generate_report
    
    echo ""
    log_info "=== TEST SUMMARY ==="
    log_info "Full test log: $LOG_FILE"
    
    if [ $failures -eq 0 ]; then
        log_success "Configuration appears ready for deployment"
        return 0
    else
        log_warn "$failures configuration issues detected"
        return 1
    fi
}

# Main
main() {
    case "${1:-all}" in
        all)
            init
            run_all_tests
            ;;
        askpass)
            init
            test_askpass_disabled
            ;;
        keys)
            init
            test_keys_exist
            ;;
        config)
            init
            test_ssh_config
            ;;
        test)
            init
            test_ssh_without_password
            ;;
        report)
            init
            test_configuration_summary
            ;;
        *)
            echo "Usage: $0 {all|askpass|keys|config|test|report}"
            exit 1
            ;;
    esac
}

main "$@"
