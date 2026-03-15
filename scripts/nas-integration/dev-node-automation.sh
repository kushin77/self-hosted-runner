#!/bin/bash
#
# 🚀 ONE-COMMAND DEV NODE SETUP & QUICK OPERATIONS
#
# This script automates common dev node operations and integrates with NAS
#
# Usage:
#   bash dev-node-automation.sh setup       # Full setup
#   bash dev-node-automation.sh push        # Push to NAS  
#   bash dev-node-automation.sh diff        # Show changes
#   bash dev-node-automation.sh watch       # Watch mode
#   bash dev-node-automation.sh health      # Health check
#   bash dev-node-automation.sh help        # Show help
#

set -euo pipefail

# Configuration
readonly OPT_AUTOMATION="${OPT_AUTOMATION:-/opt/automation}"
readonly OPT_IAC="${OPT_IAC:-/opt/iac-configs}"
readonly LOG_DIR="${LOG_DIR:-/var/log/nas-integration}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
error() { echo -e "${RED}❌${NC} $*" >&2; exit 1; }
info() { echo -e "${MAGENTA}ℹ${NC}  $*"; }

ensure_dirs() {
  sudo mkdir -p "$LOG_DIR"
  sudo mkdir -p "$OPT_IAC"
  sudo mkdir -p "/var/audit/nas-integration"
}

# ============================================================================
# OPERATIONS
# ============================================================================

op_setup() {
  info "Running full dev node NAS integration setup..."
  sudo bash "${OPT_AUTOMATION}/scripts/nas-integration/setup-dev-node.sh"
}

op_push() {
  info "Pushing configurations to NAS..."
  ensure_dirs
  bash "${OPT_AUTOMATION}/scripts/nas-integration/dev-node-nas-push.sh" push
}

op_diff() {
  info "Showing pending changes..."
  bash "${OPT_AUTOMATION}/scripts/nas-integration/dev-node-nas-push.sh" diff
}

op_watch() {
  info "Starting watch mode (continuous sync)..."
  bash "${OPT_AUTOMATION}/scripts/nas-integration/dev-node-nas-push.sh" watch
}

op_health() {
  info "Running health check..."
  sudo bash "${OPT_AUTOMATION}/scripts/nas-integration/healthcheck-worker-nas.sh" --verbose
}

op_logs() {
  info "Showing recent logs..."
  tail -n 50 "${LOG_DIR}/dev-node-push.log" 2>/dev/null || echo "No logs yet"
  echo ""
  info "Live log (press Ctrl+C to stop):"
  tail -f "${LOG_DIR}/dev-node-push.log" 2>/dev/null || echo "Waiting for logs..."
}

op_status() {
  info "Checking NAS integration status..."
  echo ""
  echo "Environment:"
  env | grep -E "NAS_|DEV_" | sort || true
  echo ""
  echo "SSH Key Status:"
  if [[ -f "/home/automation/.ssh/nas-push-key" ]]; then
    echo "  ✅ Key exists"
    echo "  Fingerprint: $(ssh-keygen -l -f /home/automation/.ssh/nas-push-key 2>/dev/null || echo 'N/A')"
  else
    echo "  ❌ Key not found"
  fi
  echo ""
  echo "Directories:"
  echo "  IAC: $(test -d "$OPT_IAC" && echo "✅" || echo "❌") $OPT_IAC"
  echo "  Logs: $(test -d "$LOG_DIR" && echo "✅" || echo "❌") $LOG_DIR"
  echo ""
  echo "Systemd Services:"
  sudo systemctl list-units --type=service --all | grep nas- || echo "  None active"
}

op_connectivity() {
  info "Testing NAS connectivity..."
  
  local key="/home/automation/.ssh/nas-push-key"
  
  if [[ ! -f "$key" ]]; then
    error "SSH key not found: $key"
  fi
  
  local nas_host="${NAS_HOST:-192.168.168.100}"
  local nas_user="${NAS_USER:-elevatediq-svc-nas}"
  
  if ssh -i "$key" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 \
    "${nas_user}@${nas_host}" \
    "echo 'NAS reachable'; date" &>/dev/null; then
    success "Connected to NAS successfully"
  else
    error "Cannot reach NAS - check SSH key or NAS availability"
  fi
}

op_docs() {
  info "Opening documentation..."
  local docs=(
    "${OPT_AUTOMATION}/DEV_NODE_QUICKSTART.md"
    "${OPT_AUTOMATION}/docs/nas-integration/NAS_INTEGRATION_COMPLETE.md"
  )
  
  for doc in "${docs[@]}"; do
    if [[ -f "$doc" ]]; then
      echo "Found: $doc"
    fi
  done
}

op_help() {
  cat <<'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                  Dev Node Automation & NAS Operations                      ║
╚════════════════════════════════════════════════════════════════════════════╝

OPERATIONS:

  setup           - Full dev node NAS integration setup (requires sudo)
  push            - Push IAC configs to NAS
  diff            - Show pending changes
  watch           - Enable continuous watch mode (auto-push on changes)
  health          - Run health check
  logs            - View integration logs
  status          - Check NAS integration status
  connectivity    - Test NAS connectivity
  docs            - Show available documentation
  help            - Show this help

EXAMPLES:

  # First time setup
  sudo bash dev-node-automation.sh setup

  # Edit configs
  vim /opt/iac-configs/terraform/main.tf

  # Push to NAS
  bash dev-node-automation.sh push

  # Enable watch mode (continuous sync)
  bash dev-node-automation.sh watch

  # Check what changed
  bash dev-node-automation.sh diff

  # Monitor logs
  bash dev-node-automation.sh logs

  # Test NAS connectivity
  bash dev-node-automation.sh connectivity

DATA FLOW:

  You Edit Files              NAS Server              Worker Nodes
  /opt/iac-configs/  ----[push]--->  /repositories/iac/  ---[pull (30min)]---> /opt/nas-sync/

ENVIRONMENT VARIABLES:

  NAS_HOST=192.168.168.100      - NAS server IP
  NAS_PORT=22                   - SSH port
  NAS_USER=elevatediq-svc-nas              - NAS SSH user
  OPT_AUTOMATION=/opt/automation - Automation directory
  OPT_IAC=/opt/iac-configs      - Local IAC directory
  LOG_DIR=/var/log/nas-integration - Logs directory

KEY PATHS:

  SSH Key:      /home/automation/.ssh/nas-push-key
  Local IAC:    /opt/iac-configs/
  Logs:         /var/log/nas-integration/
  Scripts:      /opt/automation/scripts/nas-integration/

QUICK START:

  1. sudo bash dev-node-automation.sh setup
  2. cd /opt/iac-configs
  3. Edit your infrastructure configs
  4. bash dev-node-automation.sh push
  5. Wait 30 minutes - worker nodes pull automatically
  6. bash dev-node-automation.sh logs

TROUBLESHOOTING:

  - Check NAS connectivity:    bash dev-node-automation.sh connectivity
  - View logs:                 bash dev-node-automation.sh logs
  - Check status:              bash dev-node-automation.sh status
  - Review full docs:          bash dev-node-automation.sh docs

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local operation="${1:-help}"
  
  case "$operation" in
    setup)       op_setup ;;
    push)        op_push ;;
    diff)        op_diff ;;
    watch)       op_watch ;;
    health)      op_health ;;
    logs)        op_logs ;;
    status)      op_status ;;
    connectivity) op_connectivity ;;
    docs)        op_docs ;;
    help|*)      op_help ;;
  esac
}

main "$@"
