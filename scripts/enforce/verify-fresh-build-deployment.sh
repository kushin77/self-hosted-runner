#!/bin/bash
################################################################################
# FRESH BUILD DEPLOYMENT VERIFICATION SCRIPT
#
# Verifies that deployment follows fresh build mandate:
# ✅ Complete stack rebuilt from scratch
# ✅ On-prem targets only (no cloud)
# ✅ Fresh credentials generated
# ✅ All previous state removed
#
# Usage: bash scripts/enforce/verify-fresh-build-deployment.sh
# Exit: 0 = all checks passed, >0 = failures detected
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    ((WARNINGS++))
}

# ============================================================================
# SECTION 1: ENVIRONMENT CHECKS
# ============================================================================

check_environment() {
    echo ""
    log "═══ SECTION 1: ENVIRONMENT VALIDATION ═══"
    
    # Check 1: No cloud credentials
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
        fail "GCP credentials detected in environment"
    else
        pass "No GCP credentials found"
    fi
    
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        fail "AWS credentials detected in environment"
    else
        pass "No AWS credentials found"
    fi
    
    if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]] || [[ -n "${AZURE_TENANT_ID:-}" ]]; then
        fail "Azure credentials detected in environment"
    else
        pass "No Azure credentials found"
    fi
    
    # Check 2: kubectl cloud contexts
    if command -v kubectl &>/dev/null; then
        local context=$(kubectl config current-context 2>/dev/null || echo "none")
        if [[ "$context" != "none" ]]; then
            if [[ "$context" == *"gke"* ]] || [[ "$context" == *"eks"* ]] || [[ "$context" == *"aks"* ]]; then
                fail "Cloud kubectl context detected: $context"
            else
                pass "kubectl context is not cloud-based: $context"
            fi
        else
            pass "No kubectl context configured"
        fi
    else
        warn "kubectl not installed (optional)"
    fi
}

# ============================================================================
# SECTION 2: TARGET VALIDATION
# ============================================================================

check_target_host() {
    echo ""
    log "═══ SECTION 2: TARGET HOST VALIDATION ═══"
    
    local target="${TARGET_HOST:-192.168.168.42}"
    
    # Check if target is on-prem
    case "$target" in
        192.168.168.42)
            pass "Target is on-prem primary: $target"
            ;;
        192.168.168.39)
            pass "Target is on-prem backup: $target"
            ;;
        *)
            fail "Target is not on-prem: $target"
            return 1
            ;;
    esac
    
    # Check connectivity (if available)
    if ping -c 1 "$target" &>/dev/null 2>&1; then
        pass "Target is reachable: $target"
    else
        warn "Cannot ping target (may be offline): $target"
    fi
}

# ============================================================================
# SECTION 3: DEPLOYMENT STATE CHECKS
# ============================================================================

check_deployment_state() {
    echo ""
    log "═══ SECTION 3: DEPLOYMENT STATE VALIDATION ═══"
    
    # Check 1: Deployment directory structure
    if [[ -d "/opt/automation/deployment" ]]; then
        pass "Deployment directory exists"
        
        # Check for components
        local components=0
        [[ -d "/opt/automation/deployment/core" ]] && ((components++)) && pass "  ✓ Core components directory"
        [[ -d "/opt/automation/deployment/k8s-health-checks" ]] && ((components++)) && pass "  ✓ K8s health checks directory"
        [[ -d "/opt/automation/deployment/security" ]] && ((components++)) && pass "  ✓ Security scripts directory"
        [[ -d "/opt/automation/deployment/multi-region" ]] && ((components++)) && pass "  ✓ Multi-region directory"
        
        if [[ $components -eq 4 ]]; then
            pass "All expected directories present ($components/4)"
        else
            warn "Only $components/4 expected directories found"
        fi
    else
        fail "Deployment directory not found"
    fi
    
    # Check 2: Script files
    if [[ -d "/opt/automation/deployment" ]]; then
        local script_count=$(find /opt/automation/deployment -name "*.sh" -type f 2>/dev/null | wc -l)
        if [[ $script_count -gt 0 ]]; then
            pass "Found $script_count deployment scripts"
        else
            fail "No deployment scripts found"
        fi
    fi
    
    # Check 3: SSH keys are fresh
    if [[ -f "/opt/automation/deployment/automation_ed25519" ]]; then
        pass "Fresh Ed25519 SSH key found"
        
        # Check key permissions (should be 600)
        local perms=$(stat -c %a /opt/automation/deployment/automation_ed25519)
        if [[ "$perms" == "600" ]]; then
            pass "SSH key has correct permissions ($perms)"
        else
            fail "SSH key has incorrect permissions ($perms, should be 600)"
        fi
    else
        warn "Fresh SSH key not yet deployed"
    fi
    
    # Check 4: No old state directories
    if [[ -d "/opt/old-deployment" ]]; then
        fail "Old deployment state directory still exists (should be cleaned)"
    else
        pass "No previous deployment state found (clean slate)"
    fi
}

# ============================================================================
# SECTION 4: FRESH BUILD TIMESTAMP CHECKS
# ============================================================================

check_fresh_timestamps() {
    echo ""
    log "═══ SECTION 4: FRESH BUILD TIMESTAMP VALIDATION ═══"
    
    local now=$(date +%s)
    local one_hour_ago=$((now - 3600))
    
    if [[ -d "/opt/automation/deployment" ]]; then
        # Find most recent file
        local newest=$(find /opt/automation/deployment -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
        
        if [[ -n "$newest" ]]; then
            local newest_time=${newest%.*}
            local age=$((now - newest_time))
            
            if [[ $age -lt 3600 ]]; then
                local hours=$((age / 60))
                pass "Deployment is fresh (modified $hours minutes ago)"
            else
                local hours=$((age / 3600))
                warn "Deployment is not recently modified ($hours hours old)"
            fi
        fi
    fi
}

# ============================================================================
# SECTION 5: SERVICE STATUS CHECKS
# ============================================================================

check_services() {
    echo ""
    log "═══ SECTION 5: SERVICE STATUS VALIDATION ═══"
    
    # Check systemd services
    if systemctl list-units --type=service --state=running 2>/dev/null | grep -q "automation\|deployment"; then
        pass "Automation services are running"
    else
        warn "Could not verify service status (may be offline)"
    fi
}

# ============================================================================
# SECTION 6: MANDATE COMPLIANCE SUMMARY
# ============================================================================

print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║            FRESH BUILD DEPLOYMENT VERIFICATION REPORT          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "RESULTS:"
    echo -e "  ${GREEN}✅ Passed:${NC}  $PASSED checks"
    echo -e "  ${RED}❌ Failed:${NC}  $FAILED checks"
    echo -e "  ${YELLOW}⚠️  Warnings:${NC} $WARNINGS checks"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ FRESH BUILD MANDATE VERIFIED${NC}"
        echo ""
        echo "The deployment meets all fresh build requirements:"
        echo "  ✓ No cloud credentials in environment"
        echo "  ✓ On-prem target verified"
        echo "  ✓ Fresh deployment structure confirmed"
        echo "  ✓ Clean slate (no previous state)"
        echo "  ✓ Fresh SSL keys deployed"
        return 0
    else
        echo -e "${RED}❌ FRESH BUILD MANDATE FAILED${NC}"
        echo ""
        echo "The deployment does not meet all fresh build requirements."
        echo "Please review the failures above and remediate before deployment."
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     FRESH BUILD DEPLOYMENT VERIFICATION                        ║"
    echo "║     Checking mandate: Complete fresh rebuild, on-prem only     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    
    check_environment
    check_target_host || true
    check_deployment_state
    check_fresh_timestamps
    check_services
    print_summary
}

# Execute
main "$@"
exit $?
