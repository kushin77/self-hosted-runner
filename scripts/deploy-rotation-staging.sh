#!/usr/bin/env bash
set -euo pipefail

# Deploy Rotation Automation to Staging - Hands-Off Automation Script
# Usage: ./scripts/deploy-rotation-staging.sh [--inventory <path>] [--check] [--verbose]
#
# Features:
#   - Auto-detects inventory file if not specified
#   - Validates inventory and connectivity
#   - Runs syntax-check, dry-run, then full deploy (idempotent)
#   - Verifies service status and metrics post-deploy
#   - Supports check mode (--check) for safe dry-runs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY_FILE=""
CHECK_MODE=false
VERBOSE=false
DRY_RUN=false
ANSIBLE_USER="${ANSIBLE_USER:-root}"
# Optional: path to a private key file to use for SSH; can be provided via
# --ssh-key-file or the ANSIBLE_SSH_KEY environment variable (contents).
SSH_KEY_FILE=""
TMP_SSH_KEY=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ${NC}  $*"
}

log_success() {
  echo -e "${GREEN}✓${NC}  $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC}  $*"
}

log_error() {
  echo -e "${RED}✗${NC}  $*" >&2
}

# Parse command-line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --inventory)
        INVENTORY_FILE="$2"
        shift 2
        ;;
      --check)
        CHECK_MODE=true
        DRY_RUN=true
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
      --ssh-key-file)
        SSH_KEY_FILE="$2"
        shift 2
        ;;
      --ssh-key)
        # Accept raw private key content on the CLI (be careful)
        TMP_SSH_KEY="$(cat -)"
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

show_help() {
  cat <<'EOF'
Deploy Rotation Automation to Staging - Ansible Automation Script

Usage: deploy-rotation-staging.sh [OPTIONS]

Options:
  --inventory <path>    Path to Ansible inventory file (auto-detected if omitted)
  --check               Run in check mode (dry-run only, no actual deploy)
  --dry-run             Run syntax-check and dry-run, then stop (no actual deploy)
  --verbose             Enable verbose output
  -h, --help            Show this help message

Environment Variables:
  ANSIBLE_SSH_KEY      Path to SSH private key (optional; Ansible will use agent if omitted)
  ANSIBLE_USER         Ansible SSH user (default: root)

Examples:
  # Auto-detect inventory and run full deploy
  ./scripts/deploy-rotation-staging.sh

  # Use specific inventory file
  ./scripts/deploy-rotation-staging.sh --inventory ansible/inventory/staging-prod

  # Dry-run only (check mode)
  ./scripts/deploy-rotation-staging.sh --check

  # Full deploy with verbose logging
  ./scripts/deploy-rotation-staging.sh --verbose

EOF
}

# Auto-detect inventory file
detect_inventory() {
  if [ -n "$INVENTORY_FILE" ]; then
    return 0
  fi

  local candidates=(
    "ansible/inventory/staging"
    "ansible/inventory/staging.yml"
    "ansible/inventory/staging.yaml"
    "ansible/hosts.staging"
  )

  for candidate in "${candidates[@]}"; do
    if [ -f "$SCRIPT_DIR/$candidate" ]; then
      INVENTORY_FILE="$candidate"
      log_success "Auto-detected inventory: $INVENTORY_FILE"
      return 0
    fi
  done

  log_error "Could not auto-detect inventory file. Tried:"
  for candidate in "${candidates[@]}"; do
    echo "  - $candidate"
  done
  exit 1
}

# Validate inventory file
validate_inventory() {
  local full_path="$SCRIPT_DIR/$INVENTORY_FILE"

  if [ ! -f "$full_path" ]; then
    log_error "Inventory file not found: $full_path"
    exit 1
  fi

  log_info "Validating inventory: $INVENTORY_FILE"
  cat "$full_path"
  log_success "Inventory file validated"

  # Check if inventory has 'runners' group
  if ! grep -q "runners" "$full_path"; then
    log_warn "No 'runners' group found in inventory. Playbook may not match any hosts."
  fi
}

# Run Ansible playbook
run_playbook() {
  local mode="$1"
  local extra_args=()

  case "$mode" in
    syntax-check)
      log_info "Running syntax check..."
      extra_args+=(--syntax-check)
      ;;
    check)
      log_info "Running in check mode (dry-run)..."
      extra_args+=(--check)
      ;;
    deploy)
      if [ "$DRY_RUN" = true ]; then
        log_warn "Dry-run mode enabled; skipping actual deployment"
        return 0
      fi
      log_info "Running full deployment (apply mode)..."
      ;;
  esac

  if [ "$VERBOSE" = true ]; then
    extra_args+=(-vv)
  fi

  # Prepare SSH key if provided via env or option
  local private_key_arg=( )
  if [ -n "$SSH_KEY_FILE" ] && [ -f "$SSH_KEY_FILE" ]; then
    private_key_arg=( --private-key "$SSH_KEY_FILE" )
  elif [ -n "${ANSIBLE_SSH_KEY:-}" ]; then
    # Write key contents to temp file
    TMP_SSH_KEY="$(mktemp -p "$SCRIPT_DIR" ansible_ssh_key_XXXX)"
    echo "$ANSIBLE_SSH_KEY" > "$TMP_SSH_KEY"
    chmod 600 "$TMP_SSH_KEY"
    private_key_arg=( --private-key "$TMP_SSH_KEY" )
  elif [ -n "$TMP_SSH_KEY" ]; then
    # If user piped key via --ssh-key, TMP_SSH_KEY already set from stdin
    local keyfile="$(mktemp -p "$SCRIPT_DIR" ansible_ssh_key_XXXX)"
    echo "$TMP_SSH_KEY" > "$keyfile"
    chmod 600 "$keyfile"
    TMP_SSH_KEY="$keyfile"
    private_key_arg=( --private-key "$TMP_SSH_KEY" )
  fi

  cd "$SCRIPT_DIR"
  ansible-playbook \
    "${extra_args[@]}" \
    --inventory="$INVENTORY_FILE" \
    -u "$ANSIBLE_USER" \
    ${private_key_arg[@]} \
    --extra-vars="deploy_timestamp=$(date -Iseconds)" \
    ansible/playbooks/deploy-rotation.yml

  log_success "Playbook completed successfully"
}

# Verify deployment
verify_deployment() {
  if [ "$DRY_RUN" = true ]; then
    log_warn "Skipping verification in dry-run mode"
    return 0
  fi

  log_info "Verifying deployment..."

  cd "$SCRIPT_DIR"
  if ansible \
    --inventory="$INVENTORY_FILE" \
    -u "$ANSIBLE_USER" \
    ${private_key_arg[@]} \
    runners \
    -m command \
    -a "systemctl is-active vault-integration.service" \
    > /dev/null 2>&1; then
    log_success "Service vault-integration is active on all hosts"
  else
    log_warn "Service vault-integration not confirmed active. Check manually with:"
    echo "  ansible -i $INVENTORY_FILE runners -m command -a 'systemctl status vault-integration.service'"
  fi
}

# Main execution
main() {
  parse_args "$@"
  detect_inventory
  validate_inventory

  log_info "Starting deployment automation..."
  log_info "Deployment mode: $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (no apply)' || echo 'FULL DEPLOY')"

  run_playbook syntax-check
  run_playbook check
  run_playbook deploy

  verify_deployment

  if [ "$DRY_RUN" = true ]; then
    log_warn "This was a dry-run. To execute the full deployment, run:"
    echo "  $0 --inventory $INVENTORY_FILE"
  else
    log_success "Deployment completed! Monitor Prometheus for runner_rotation_failures (should be 0)"
    log_success "Check metrics dashboard for vault_rotation_success_total incrementing every hour"
  fi
}

main "$@"
