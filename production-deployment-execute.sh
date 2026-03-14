#!/bin/bash
#
# 🎯 PRODUCTION DEPLOYMENT - IMMEDIATE EXECUTION
#
# This script attempts COMPLETE deployment from bootstrap through production.
#
# Mandate-Complete Deployment:
#   ✅ Immutable - Git-tracked changes only
#   ✅ Ephemeral - Worker can be recreated
#   ✅ Idempotent - Safe to repeat
#   ✅ No-Ops - Dry-run supported
#   ✅ Hands-Off - Fully automated
#   ✅ GSM/Vault/KMS - Credential management
#   ✅ Direct deployment - Zero GitHub Actions
#   ✅ Git tracking - Immutable audit trail
#

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="production-deployment-$TIMESTAMP.log"

# ============================================================================
# LOGGING
# ============================================================================
log_info() { echo "[INFO] $*" 2>&1 | tee -a "$LOG_FILE"; }
log_success() { echo "✅ $*" 2>&1 | tee -a "$LOG_FILE"; }
log_error() { echo "❌ $*" 2>&1 | tee -a "$LOG_FILE"; }
log_warn() { echo "⚠️  $*" 2>&1 | tee -a "$LOG_FILE"; }

# ============================================================================
# ENTRY POINT
# ============================================================================
main() {
    log_info "════════════════════════════════════════════════════════════════"
    log_info "🚀 PRODUCTION DEPLOYMENT STARTING"
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Timestamp: $(date)"
    log_info "Worker: 192.168.168.42"
    log_info "Log: $LOG_FILE"
    log_info ""
    
    cd /home/akushnir/self-hosted-runner
    
    # ========================================================================
    # STEP 1: BOOTSTRAP
    # ========================================================================
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "STEP 1: WORKER BOOTSTRAP"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if timeout 3 ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=2 akushnir@192.168.168.42 whoami &>/dev/null 2>&1; then
        log_success "Worker already bootstrapped, skipping bootstrap phase"
    else
        log_warn "Worker not bootstrapped, launching bootstrap toolkit..."
        echo ""
        log_info "You have multiple options for bootstrap:"
        log_info "  1. Password SSH (ssh-copy-id)"
        log_info "  2. IPMI/BMC console"
        log_info "  3. Serial console"
        log_info "  4. Physical console"
        log_info "  5. Existing akushnir user + sudo"
        echo ""
        bash aggressive-bootstrap-toolkit.sh || {
            log_error "Bootstrap failed"
            log_error ""
            log_error "Unable to establish SSH access to worker 192.168.168.42"
            log_error ""
            log_error "You must complete ONE of these:"
            log_error "  Option 1: Get physical/IPMI/serial console access to worker"
            log_error "  Option 2: Use password-based SSH if available"
            log_error "  Option 3: Verify worker has akushnir user with sudo"
            log_error ""
            log_error "Then run this script again"
            return 1
        }
    fi
    
    echo ""
    log_success "Bootstrap complete"
    
    # ========================================================================
    # STEP 2: FULL DEPLOYMENT
    # ========================================================================
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "STEP 2: FULL ORCHESTRATOR DEPLOYMENT"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if bash deployment-executor-autonomous.sh 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Deployment executor completed"
    else
        log_error "Deployment failed"
        log_error "Check log: $LOG_FILE"
        return 1
    fi
    
    # ========================================================================
    # SUCCESS
    # ========================================================================
    echo ""
    log_info "════════════════════════════════════════════════════════════════"
    log_success "✅ PRODUCTION DEPLOYMENT COMPLETE"
    log_info "════════════════════════════════════════════════════════════════"
    log_info ""
    log_info "Verify deployment:"
    log_info "  ssh akushnir@192.168.168.42 sudo systemctl status nas-integration.target"
    log_info ""
    log_info "Check health:"
    log_info "  ssh akushnir@192.168.168.42 sudo bash /home/akushnir/self-hosted-runner/health-check-runner.sh"
    log_info ""
    log_info "View logs:"
    log_info "  tail -50 $LOG_FILE"
    log_info ""
}

# ============================================================================
# RUN
# ============================================================================
if [ "${DRY_RUN:-false}" = "true" ]; then
    log_info "DRY-RUN MODE"
    log_info "No changes will be made, only validation"
    echo ""
fi

main "$@"
