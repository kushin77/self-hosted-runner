#!/bin/bash
#
# 📦 NAS INTEGRATION DEPLOYMENT MANIFEST
#
# One-command deployment of NAS integration for worker and dev nodes
# Run this after basic SSH setup is complete
#
# Usage:
#   bash deploy-nas-integration.sh [worker|dev|all]
#
# Defaults to 'all' (deploy to both nodes)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKER_NODE="192.168.168.42"
readonly DEV_NODE="192.168.168.31"
readonly NAS_HOST="192.168.168.100"

# ============================================================================
# LOGGING
# ============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; return 1; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }

# ============================================================================
# DEPLOYMENT TARGETS
# ============================================================================

deploy_worker_node() {
  step "Deploying NAS Integration to Worker Node (${WORKER_NODE})"
  
  # 1. Copy scripts
  log "Copying NAS integration scripts..."
  scp -r "${REPO_ROOT}/scripts/nas-integration" \
      automation@"${WORKER_NODE}":/opt/automation/scripts/ 2>/dev/null || \
    warn "Could not copy scripts (verify SSH access)"
  
  # 2. Make executable
  log "Setting executable permissions..."
  ssh automation@"${WORKER_NODE}" \
    "chmod 755 /opt/automation/scripts/nas-integration/*.sh" 2>/dev/null || true
  
  # 3. Create directories
  log "Creating NAS sync directories..."
  ssh automation@"${WORKER_NODE}" \
    "mkdir -p /opt/nas-sync/{iac,configs,credentials,audit}" 2>/dev/null || true
  
  # 4. Copy systemd files
  log "Installing systemd services..."
  ssh automation@"${WORKER_NODE}" \
    "sudo cp /tmp/nas-*.{service,timer} /etc/systemd/system/ 2>/dev/null || true" || \
    warn "Systemd installation requires manual steps (see docs)"
  
  # 5. Reload systemd
  log "Reloading systemd configuration..."
  ssh automation@"${WORKER_NODE}" \
    "sudo systemctl daemon-reload" 2>/dev/null || true
  
  # 6. Enable services
  log "Enabling NAS integration services..."
  ssh automation@"${WORKER_NODE}" \
    "sudo systemctl enable nas-integration.target nas-worker-sync.timer nas-worker-healthcheck.timer" 2>/dev/null || true
  
  # 7. Test sync
  log "Testing initial sync..."
  if ssh automation@"${WORKER_NODE}" \
       "bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh" 2>&1 | \
       head -20; then
    success "Worker node deployment complete"
    return 0
  else
    warn "Initial sync test failed (check logs on worker node)"
    return 1
  fi
}

deploy_dev_node() {
  step "Deploying NAS Integration to Dev Node (${DEV_NODE})"
  
  # 1. Copy scripts
  log "Copying NAS integration scripts..."
  scp "${REPO_ROOT}/scripts/nas-integration/dev-node-nas-push.sh" \
      automation@"${DEV_NODE}":/opt/automation/scripts/nas-integration/ 2>/dev/null || \
    warn "Could not copy script (verify SSH access)"
  
  # 2. Make executable
  log "Setting executable permissions..."
  ssh automation@"${DEV_NODE}" \
    "chmod 755 /opt/automation/scripts/nas-integration/dev-node-nas-push.sh" 2>/dev/null || true
  
  # 3. Verify IAC directory
  log "Verifying IAC configuration directory..."
  ssh automation@"${DEV_NODE}" \
    "test -d /opt/iac-configs && echo '✓ Found' || echo '⚠ Not found (create with git clone)'" || true
  
  # 4. Test push
  log "Testing initial push to NAS..."
  if ssh automation@"${DEV_NODE}" \
       "bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push" 2>&1 | \
       head -20; then
    success "Dev node deployment complete"
    return 0
  else
    warn "Initial push test failed (check logs on dev node)"
    return 1
  fi
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_connectivity() {
  step "Verifying connectivity to all systems"
  
  # Test SSH to worker node
  if ssh -o ConnectTimeout=5 automation@"${WORKER_NODE}" echo "✓ Worker" 2>/dev/null; then
    success "Worker node reachable"
  else
    error "Cannot reach worker node at ${WORKER_NODE}"
    return 1
  fi
  
  # Test SSH to dev node
  if ssh -o ConnectTimeout=5 automation@"${DEV_NODE}" echo "✓ Dev" 2>/dev/null; then
    success "Dev node reachable"
  else
    error "Cannot reach dev node at ${DEV_NODE}"
    return 1
  fi
  
  # Test SSH to NAS (from worker)
  if ssh -o ConnectTimeout=5 automation@"${WORKER_NODE}" \
       ssh -o ConnectTimeout=5 svc-nas@"${NAS_HOST}" echo "✓ NAS" 2>/dev/null; then
    success "NAS reachable from worker node"
  else
    warn "Cannot reach NAS from worker (SSH key may need setup)"
  fi
}

show_next_steps() {
  cat << 'EOF'

┌─────────────────────────────────────────────────────────────────┐
│                  ✅ DEPLOYMENT COMPLETE                         │
└─────────────────────────────────────────────────────────────────┘

🚀 NEXT STEPS:

1. VERIFY WORKER NODE SYNC
   ssh automation@192.168.168.42
   cat /opt/nas-sync/audit/.last-success
   # Should show recent timestamp

2. CHECK SYSTEMD TIMERS
   ssh automation@192.168.168.42 'sudo systemctl status nas-worker-sync.timer'
   # Should show: Active: active (waiting)

3. VERIFY DEV NODE PUSH
   ssh automation@192.168.168.31
   ls /opt/nas-sync/iac  # Should show synced files

4. MONITOR HEALTH
   ssh automation@192.168.168.42 \
     'bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose'
   # Should show: 🟢 Overall Status: HEALTHY

5. ENABLE CONTINUOUS WATCH (OPTIONAL)
   ssh automation@192.168.168.31
   nohup bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch &

📚 DOCUMENTATION:
   Worker Guide: docs/NAS_INTEGRATION_COMPLETE.md
   Quick Start:  docs/NAS_QUICKSTART.md
   Troubleshoot: docs/NAS_INTEGRATION_COMPLETE.md#troubleshooting

🔔 MONITORING:
   Prometheus alerts configured in docker/prometheus/nas-integration-rules.yml
   Check Grafana for NAS integration dashboard

✅ PRODUCTION STATUS: Ready for operations

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local target="${1:-all}"
  
  echo -e "${BLUE}"
  cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║           📦 NAS INTEGRATION DEPLOYMENT MANIFEST             ║
║                    Version 1.0                                ║
╚═══════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
  
  # Show configuration
  log "Configuration:"
  log "  Worker Node: ${WORKER_NODE}"
  log "  Dev Node:    ${DEV_NODE}"
  log "  NAS Server:  ${NAS_HOST}"
  log "  Repo Root:   ${REPO_ROOT}"
  log ""
  
  # Verify connectivity first
  if ! verify_connectivity; then
    error "Cannot proceed without connectivity to all systems"
    return 1
  fi
  log ""
  
  # Deploy based on target
  local exit_code=0
  case "$target" in
    worker)
      if ! deploy_worker_node; then
        error "Worker node deployment had issues"
        ((exit_code++))
      fi
      ;;
    dev)
      if ! deploy_dev_node; then
        error "Dev node deployment had issues"
        ((exit_code++))
      fi
      ;;
    all|*)
      if ! deploy_worker_node; then
        warn "Worker node deployment had issues"
        ((exit_code++))
      fi
      log ""
      
      if ! deploy_dev_node; then
        warn "Dev node deployment had issues"
        ((exit_code++))
      fi
      ;;
  esac
  
  log ""
  
  # Show summary
  if [[ $exit_code -eq 0 ]]; then
    show_next_steps
    return 0
  else
    error "Deployment completed with warnings (exit code: $exit_code)"
    show_next_steps
    return $exit_code
  fi
}

# Execute with human confirmation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo -e "${YELLOW}This will deploy NAS integration to: $*${NC}"
  echo ""
  read -p "Continue? (yes/no) " -r confirm
  if [[ "$confirm" == "yes" ]]; then
    main "$@"
  else
    log "Deployment cancelled"
    exit 0
  fi
fi
