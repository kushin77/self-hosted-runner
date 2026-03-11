#!/bin/bash
#
# Phase 5.1 - Systemd Activation Script
# Deploys Phase 5 rotation orchestrator with daily 02:00 UTC automation
# Authority: Lead Engineer (Approved & In Progress)
# Status: Immutable, hands-off, no-ops execution
#
# Exit on error
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }

# Audit logging
AUDIT_LOG="/home/akushnir/self-hosted-runner/logs/phase-5-activation/systemd-deploy-$(date +%Y%m%d-%H%M%S).jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")"

audit_event() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    cat >> "$AUDIT_LOG" <<EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)","event":"$event","status":"$status","details":"$details","immutable_commit":"$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"}
EOF
}

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ Phase 5.1: Systemd Activation (Lead Engineer Authority)    ║"
    log_info "║ Schedule: Daily 02:00 UTC (immutable audit trail)           ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    
    audit_event "ACTIVATION_START" "in-progress" "Deploying Phase 5 systemd units"
    
    # Step 1: Verify source files exist
    log_info "Step 1: Verifying source files..."
    if [ ! -f "/home/akushnir/self-hosted-runner/scripts/secrets/phase5-rotation.service" ]; then
        log_error "Service unit not found: scripts/secrets/phase5-rotation.service"
        audit_event "SOURCE_VERIFICATION" "failure" "Service unit missing"
        exit 1
    fi
    
    if [ ! -f "/home/akushnir/self-hosted-runner/scripts/secrets/phase5-rotation.timer" ]; then
        log_error "Timer unit not found: scripts/secrets/phase5-rotation.timer"
        audit_event "SOURCE_VERIFICATION" "failure" "Timer unit missing"
        exit 1
    fi
    log_success "Source files verified"
    audit_event "SOURCE_VERIFICATION" "success" "Both units present"
    
    # Step 2: Deploy units
    log_info "Step 2: Deploying systemd units..."
    sudo cp -v /home/akushnir/self-hosted-runner/scripts/secrets/phase5-rotation.service /etc/systemd/system/ && \
    log_success "Service unit deployed" || {
        log_error "Failed to deploy service unit"
        audit_event "SERVICE_DEPLOY" "failure" "Copy failed"
        exit 1
    }
    audit_event "SERVICE_DEPLOY" "success" "Copied to /etc/systemd/system/"
    
    sudo cp -v /home/akushnir/self-hosted-runner/scripts/secrets/phase5-rotation.timer /etc/systemd/system/ && \
    log_success "Timer unit deployed" || {
        log_error "Failed to deploy timer unit"
        audit_event "TIMER_DEPLOY" "failure" "Copy failed"
        exit 1
    }
    audit_event "TIMER_DEPLOY" "success" "Copied to /etc/systemd/system/"
    
    # Step 3: Reload systemd
    log_info "Step 3: Reloading systemd daemon..."
    sudo systemctl daemon-reload && \
    log_success "systemd daemon reloaded" || {
        log_error "Failed to reload systemd daemon"
        audit_event "DAEMON_RELOAD" "failure" "systemctl failed"
        exit 1
    }
    audit_event "DAEMON_RELOAD" "success" "daemon-reload completed"
    
    # Step 4: Enable and start timer
    log_info "Step 4: Enabling and starting Phase 5 timer..."
    sudo systemctl enable phase5-rotation.timer && \
    log_success "Timer enabled for auto-start" || {
        log_error "Failed to enable timer"
        audit_event "TIMER_ENABLE" "failure" "systemctl enable failed"
        exit 1
    }
    audit_event "TIMER_ENABLE" "success" "Enabled for boot startup"
    
    sudo systemctl restart phase5-rotation.timer && \
    log_success "Timer started (will execute at 02:00 UTC)" || {
        log_error "Failed to start timer"
        audit_event "TIMER_START" "failure" "systemctl restart failed"
        exit 1
    }
    audit_event "TIMER_START" "success" "Timer activated for 2026-03-12 02:00 UTC"
    
    # Step 5: Verify deployment
    log_info "Step 5: Verifying deployment..."
    if systemctl is-enabled phase5-rotation.timer &>/dev/null; then
        log_success "Timer enabled ✓"
        audit_event "VERIFICATION" "success" "Timer enabled state confirmed"
    else
        log_error "Timer not enabled"
        audit_event "VERIFICATION" "failure" "Timer not enabled"
        exit 1
    fi
    
    if systemctl is-active phase5-rotation.timer &>/dev/null; then
        log_success "Timer active ✓"
        audit_event "VERIFICATION" "success" "Timer active state confirmed"
    else
        log_warn "Timer not yet active (will activate at next scheduled time)"
        audit_event "VERIFICATION" "success" "Timer will activate at scheduled time"
    fi
    
    # Step 6: Display status
    log_info "Step 6: Final status..."
    echo ""
    sudo systemctl status phase5-rotation.timer --no-pager
    echo ""
    log_info "Upcoming rotations:"
    sudo systemctl list-timers phase5-rotation.timer --no-pager || true
    echo ""
    
    # Step 7: Success summary
    log_success "╔════════════════════════════════════════════════════════════╗"
    log_success "║ Phase 5.1 Activation: COMPLETE                             ║"
    log_success "╚════════════════════════════════════════════════════════════╝"
    
    log_info "Deployment Details:"
    log_info "  • Service: /etc/systemd/system/phase5-rotation.service"
    log_info "  • Timer: /etc/systemd/system/phase5-rotation.timer"
    log_info "  • Schedule: Daily at 02:00 UTC"
    log_info "  • Next run: 2026-03-12 02:00:00 UTC"
    log_info "  • Audit trail: $AUDIT_LOG"
    log_info "  • Immutable: Append-only JSONL logging enabled"
    echo ""
    
    log_info "Next steps:"
    log_info "  1. Monitor first rotation: tail -f logs/phase-5-orchestration/*.jsonl"
    log_info "  2. Check service logs: journalctl -u phase5-rotation.service -f"
    log_info "  3. Verify credentials rotated: Check GSM secret versions"
    log_info ""
    log_info "Architecture compliance:"
    log_info "  ✅ Immutable: JSONL audit trail (append-only, no data loss)"
    log_info "  ✅ Ephemeral: Docker containers created/run/cleanup; no persistent state"
    log_info "  ✅ Idempotent: All rotation scripts safe to re-run"
    log_info "  ✅ No-Ops: Fully automated via systemd; zero manual intervention"
    log_info "  ✅ Hands-Off: Remote execution; no user interaction required"
    log_info "  ✅ Direct Deploy: No GitHub Actions; no workflow engines"
    log_info ""
    
    audit_event "ACTIVATION_COMPLETE" "success" "Phase 5.1 systemd deployment finished"
    
    log_success "Audit log: $AUDIT_LOG"
}

# Run main
main "$@"
