#!/bin/bash

###############################################################################
# DEPLOYMENT-READINESS-CHECK.SH
#
# Comprehensive pre-deployment verification script.
# Checks all prerequisites and reports readiness status.
#
# Exit codes:
#   0 = Ready for deployment
#   1 = Missing critical prerequisites
#   2 = Warnings present but deployment possible
#
# Usage:
#   bash scripts/deployment-readiness-check.sh [--fix] [--verbose]
#
###############################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(dirname "$SCRIPT_DIR")"
readonly DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
readonly DEPLOY_USER="${DEPLOY_USER:-runner}"
readonly VERBOSE="${VERBOSE:-false}"
readonly FIX_ISSUES="${FIX_ISSUES:-false}"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# tracking
declare -i CRITICAL_ISSUES=0
declare -i WARNINGS=0
declare -i CHECKS_PASSED=0

###############################################################################
# LOGGING FUNCTIONS
###############################################################################

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
pass() { 
    echo -e "${GREEN}✅ PASS${NC}  : $*"
    ((CHECKS_PASSED++))
}
warn() { 
    echo -e "${YELLOW}⚠️  WARN${NC}  : $*"
    ((WARNINGS++))
}
fail() { 
    echo -e "${RED}❌ FAIL${NC}  : $*"
    ((CRITICAL_ISSUES++))
}
debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}DEBUG${NC}: $*" || true; }

###############################################################################
# INDIVIDUAL CHECKS
###############################################################################

check_gcloud() {
    log "Checking Google Cloud CLI..."
    if command -v gcloud &>/dev/null; then
        local version
        version=$(gcloud version --format='value(gcloud)')
        pass "gcloud CLI installed: v$version"
        
        # Check auth
        if gcloud auth list --filter=status:ACTIVE --format='value(account)' &>/dev/null; then
            local account
            account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)
            pass "gcloud authenticated: $account"
        else
            fail "gcloud not authenticated. Run: gcloud auth application-default login"
        fi
    else
        fail "gcloud CLI not found. Install: curl https://sdk.cloud.google.com | bash"
    fi
}

check_gsm_secrets() {
    log "Checking Google Secret Manager secrets..."
    
    local runner_ssh_key
    local runner_ssh_user
    
    runner_ssh_key=$(gcloud secrets versions list RUNNER_SSH_KEY --limit=1 --format='value(name)' 2>/dev/null || echo "")
    runner_ssh_user=$(gcloud secrets versions list RUNNER_SSH_USER --limit=1 --format='value(name)' 2>/dev/null || echo "")
    
    if [[ -n "$runner_ssh_key" ]]; then
        pass "GSM secret exists: RUNNER_SSH_KEY (v$runner_ssh_key)"
    else
        fail "GSM secret missing: RUNNER_SSH_KEY"
    fi
    
    if [[ -n "$runner_ssh_user" ]]; then
        pass "GSM secret exists: RUNNER_SSH_USER (v$runner_ssh_user)"
    else
        fail "GSM secret missing: RUNNER_SSH_USER"
    fi
}

check_local_ssh_key() {
    log "Checking local SSH key..."
    
    local key_file="${REPO_DIR}/.ssh/runner_ed25519"
    if [[ -f "$key_file" ]]; then
        if ssh-keygen -l -f "$key_file" &>/dev/null; then
            pass "Local SSH key valid: $key_file"
        else
            fail "Local SSH key corrupt: $key_file"
        fi
    else
        warn "Local SSH key not found: $key_file"
        warn "  (This is OK if using key from GSM directly)"
    fi
}

check_network() {
    log "Checking network connectivity..."
    
    if ping -c 1 -W 2 "$DEPLOY_TARGET" &>/dev/null 2>&1; then
        pass "Network reachable: $DEPLOY_TARGET (ping)"
    else
        fail "Network unreachable: $DEPLOY_TARGET"
        return
    fi
    
    # Check SSH port
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$DEPLOY_TARGET/22" 2>/dev/null; then
        pass "SSH port open: $DEPLOY_TARGET:22"
    else
        fail "SSH port (22) not accessible on $DEPLOY_TARGET"
    fi
}

check_ssh_auth() {
    log "Checking SSH key authentication..."
    
    local key_file="$REPO_DIR/.ssh/runner_ed25519"
    if [[ ! -f "$key_file" ]]; then
        warn "Cannot test SSH auth: key file not found ($key_file)"
        return
    fi
    
    if timeout 3 ssh -i "$key_file" \
        -o ConnectTimeout=2 \
        -o StrictHostKeyChecking=accept-new \
        -o BatchMode=yes \
        "$DEPLOY_USER@$DEPLOY_TARGET" "echo OK" &>/dev/null; then
        pass "SSH authentication successful: $DEPLOY_USER@$DEPLOY_TARGET"
    else
        fail "SSH authentication failed: $DEPLOY_USER@$DEPLOY_TARGET"
        fail "  → Public key not authorized or connection refused"
        warn "  → Run scripts/provision-operator-credentials.sh to fix"
    fi
}

check_deploy_script() {
    log "Checking deployment script..."
    
    local deploy_script="$REPO_DIR/scripts/direct-deploy.sh"
    if [[ -f "$deploy_script" ]]; then
        if [[ -x "$deploy_script" ]]; then
            pass "Deploy script executable: $deploy_script"
        else
            fail "Deploy script not executable: $deploy_script"
            if [[ "$FIX_ISSUES" == "true" ]]; then
                chmod +x "$deploy_script"
                pass "  → Fixed: made executable"
            fi
        fi
    else
        fail "Deploy script not found: $deploy_script"
    fi
}

check_vault_setup() {
    log "Checking Vault Agent setup..."
    
    local vault_config="$REPO_DIR/config/vault-agent.hcl"
    local vault_template="$REPO_DIR/config/deployment.env.tpl"
    
    if [[ -f "$vault_config" ]]; then
        pass "Vault Agent config exists: config/vault-agent.hcl"
    else
        warn "Vault Agent config not found: config/vault-agent.hcl"
    fi
    
    if [[ -f "$vault_template" ]]; then
        pass "Vault template exists: config/deployment.env.tpl"
    else
        warn "Vault template not found: config/deployment.env.tpl"
    fi
}

check_disk_space() {
    log "Checking disk space..."
    
    local root_free
    local tmp_free
    
    root_free=$(df / | awk 'NR==2 {print $4}')
    tmp_free=$(df /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    
    if [[ $root_free -gt 1048576 ]]; then  # > 1GB
        pass "Root filesystem has sufficient space: $((root_free/1024))MB free"
    else
        fail "Root filesystem insufficient space: $((root_free/1024))MB free"
    fi
    
    if [[ $tmp_free -gt 2097152 ]]; then  # > 2GB
        pass "/tmp has sufficient space: $((tmp_free/1024))MB free"
    else
        warn "/tmp space low: $((tmp_free/1024))MB free (need >2GB for bundles)"
    fi
}

check_git_repo() {
    log "Checking git repository..."
    
    cd "$REPO_DIR"
    
    if git rev-parse --git-dir > /dev/null 2>&1; then
        pass "Valid git repository: $REPO_DIR"
    else
        fail "Not a git repository: $REPO_DIR"
        return
    fi
    
    if git rev-parse --abbrev-ref HEAD | grep -q "main"; then
        pass "Currently on main branch"
    else
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD)
        warn "Not on main branch: $branch"
    fi
    
    if [[ -z $(git status --porcelain) ]]; then
        pass "Working directory clean"
    else
        warn "Working directory has uncommitted changes"
    fi
}

check_audit_infrastructure() {
    log "Checking audit infrastructure..."
    
    local audit_file="$REPO_DIR/logs/deployment-provisioning-audit.jsonl"
    if [[ -f "$audit_file" ]]; then
        local lines
        lines=$(wc -l < "$audit_file")
        pass "Audit log exists: $lines entries"
    else
        warn "Audit log not found: logs/deployment-provisioning-audit.jsonl"
    fi
}

###############################################################################
# SUMMARY REPORT
###############################################################################

print_summary() {
    echo ""
    log "=========================================="
    log "DEPLOYMENT READINESS SUMMARY"
    log "=========================================="
    echo ""
    echo "  Checks Passed : $CHECKS_PASSED"
    echo "  Warnings      : $WARNINGS"
    echo "  Critical      : $CRITICAL_ISSUES"
    echo ""
    
    if [[ $CRITICAL_ISSUES -eq 0 ]]; then
        echo -e "${GREEN}✅ READY FOR DEPLOYMENT${NC}"
        echo ""
        echo "Next step:"
        echo "  bash scripts/direct-deploy.sh gsm main"
        return 0
    elif [[ $WARNINGS -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  INCOMPLETE - Manual action required${NC}"
        echo ""
        echo "Required actions:"
        echo "  1. Run: bash scripts/provision-operator-credentials.sh"
        echo "  2. Authorize SSH key on worker"
        echo "  3. Re-run: bash scripts/deployment-readiness-check.sh"
        return 1
    else
        echo -e "${YELLOW}⚠️  READY WITH WARNINGS${NC}"
        echo ""
        echo "Deployment possible but review warnings above."
        echo "To proceed safely, complete all provisioning steps."
        return 2
    fi
}

###############################################################################
# MAIN
###############################################################################

main() {
    echo ""
    log "=========================================="
    log "DEPLOYMENT READINESS CHECK"
    log "=========================================="
    log "Target: $DEPLOY_TARGET"
    log "User: $DEPLOY_USER"
    echo ""
    
    check_gcloud
    echo ""
    
    check_gsm_secrets
    echo ""
    
    check_local_ssh_key
    echo ""
    
    check_network
    echo ""
    
    check_ssh_auth
    echo ""
    
    check_deploy_script
    echo ""
    
    check_vault_setup
    echo ""
    
    check_disk_space
    echo ""
    
    check_git_repo
    echo ""
    
    check_audit_infrastructure
    echo ""
    
    print_summary
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix) FIX_ISSUES=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

main "$@"
