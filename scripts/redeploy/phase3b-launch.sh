#!/bin/bash
#
# Phase 3B: Day-2 Operations Launcher
# Orchestrates Vault AppRole and GCP Compliance automation
#
# Usage: bash scripts/redeploy/phase3b-launch.sh [OPTIONS]
#   --vault-option [a|b|c]       Option A (restore), B (create), C (skip)
#   --gcp-option [a|b|c|d]       Option A (full hardening), B (vault only), C (gcp only), D (skip both)
#   --vault-server URL            Vault server URL (for Option A)
#   --vault-root-token TOKEN      Vault root token (for Option B)
#   --gcp-project PROJECT         GCP project ID
#   --dry-run                     Show what would run, don't execute

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-false}"
VAULT_OPTION="${VAULT_OPTION:-c}"
GCP_OPTION="${GCP_OPTION:-d}"
VAULT_SERVER="${VAULT_SERVER:-}"
VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN:-}"
GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
AUDIT_DIR="${SCRIPT_DIR}/../logs/phase3b-operations"
OPERATION_ID="$(date -u +%Y%m%d-%H%M%S)-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

audit_entry() {
  local event="$1"
  local status="$2"
  local details="$3"
  
  mkdir -p "$AUDIT_DIR"
  jq -n \
    --arg event "$event" \
    --arg status "$status" \
    --arg operation_id "$OPERATION_ID" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg hostname "$(hostname)" \
    --arg user "$(whoami)" \
    --arg details "$details" \
    '{
      event, status, operation_id, timestamp, hostname, user, details
    }' >> "$AUDIT_DIR/audit-$OPERATION_ID.jsonl"
}

usage() {
  cat << USAGE
Phase 3B: Day-2 Operations Launcher

Usage: $0 [OPTIONS]

OPTIONS:
  --vault-option [a|b|c]
    a = Restore original Vault
    b = Create new local AppRole
    c = Skip Vault (default)

  --gcp-option [a|b|c|d]
    a = Full hardening (Vault + GCP)
    b = Vault only
    c = GCP only
    d = Skip both (default)

  --vault-server URL
    Vault server URL for Option A

  --vault-root-token TOKEN
    Vault root token for Option B

  --gcp-project PROJECT
    GCP project ID (default: nexusshield-prod)

  --dry-run
    Show operations without executing

EXAMPLES:
  # Skip both (safe default)
  $0

  # Full hardening (Vault restore + GCP compliance)
  $0 --vault-option a --vault-server https://vault.example.com

  # Vault only with new AppRole
  $0 --vault-option b --vault-root-token s.xxxxx

  # GCP compliance only
  $0 --gcp-option c --gcp-project my-project

USAGE
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vault-option)
        VAULT_OPTION="$2"
        shift 2
        ;;
      --gcp-option)
        GCP_OPTION="$2"
        shift 2
        ;;
      --vault-server)
        VAULT_SERVER="$2"
        shift 2
        ;;
      --vault-root-token)
        VAULT_ROOT_TOKEN="$2"
        shift 2
        ;;
      --gcp-project)
        GCP_PROJECT="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --help|-h)
        usage
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
  done
}

validate_inputs() {
  if [[ ! "$VAULT_OPTION" =~ ^[abc]$ ]]; then
    log_error "Invalid vault-option: $VAULT_OPTION (must be a, b, or c)"
    exit 1
  fi
  
  if [[ ! "$GCP_OPTION" =~ ^[abcd]$ ]]; then
    log_error "Invalid gcp-option: $GCP_OPTION (must be a, b, c, or d)"
    exit 1
  fi
  
  # Warn if Options don't align
  if [[ "$GCP_OPTION" == "a" && "$VAULT_OPTION" == "c" ]]; then
    log_warn "Full hardening (gcp-option a) requested but Vault skipped (vault-option c)"
    log_warn "Suggest: --gcp-option c (gcp-only) to avoid mixed states"
  fi
}

preflight_check() {
  log_info "Running pre-flight checks..."
  
  # Check Phase 3 deployment completed
  if ! systemctl is-active --quiet phase3-deployment.service; then
    log_warn "Phase 3 deployment service not currently active (may have completed)"
  fi
  
  # Check if nodes online
  if ! command -v curl &> /dev/null; then
    log_warn "curl not found, skipping Grafana health check"
  else
    if curl -s -f http://192.168.168.42:3000 > /dev/null 2>&1; then
      log_success "Grafana dashboard online"
    else
      log_warn "Grafana not accessible, continuing anyway"
    fi
  fi
  
  # Check audit directory
  if mkdir -p "$AUDIT_DIR"; then
    log_success "Audit directory ready: $AUDIT_DIR"
  else
    log_error "Cannot create audit directory"
    exit 1
  fi
  
  audit_entry "preflight_check" "complete" "Pre-flight validation successful"
}

execute_vault_option_a() {
  log_info "Executing Vault Option A: Restore original Vault"
  
  if [[ -z "$VAULT_SERVER" ]]; then
    log_error "Vault server URL required for Option A"
    return 1
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would execute:"
    log_info "  bash scripts/ops/OPERATOR_VAULT_RESTORE.sh --vault-server $VAULT_SERVER"
    audit_entry "vault_restore" "dry-run" "Option A: restore Vault"
    return 0
  fi
  
  if bash "$SCRIPT_DIR/ops/OPERATOR_VAULT_RESTORE.sh" \
         --vault-server "$VAULT_SERVER" \
         --immutable-audit "$AUDIT_DIR"; then
    log_success "Vault restoration completed"
    audit_entry "vault_restore" "success" "Vault AppRole restored"
    return 0
  else
    log_error "Vault restoration failed"
    audit_entry "vault_restore" "failed" "Vault AppRole restoration error"
    return 1
  fi
}

execute_vault_option_b() {
  log_info "Executing Vault Option B: Create new local AppRole"
  
  if [[ -z "$VAULT_ROOT_TOKEN" ]]; then
    log_error "Vault root token required for Option B"
    return 1
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would execute:"
    log_info "  bash scripts/ops/OPERATOR_CREATE_NEW_APPROLE.sh --vault-root-token [MASKED]"
    audit_entry "vault_create_approle" "dry-run" "Option B: create AppRole"
    return 0
  fi
  
  if bash "$SCRIPT_DIR/ops/OPERATOR_CREATE_NEW_APPROLE.sh" \
         --vault-root-token "$VAULT_ROOT_TOKEN" \
         --immutable-audit "$AUDIT_DIR"; then
    log_success "New AppRole created successfully"
    audit_entry "vault_create_approle" "success" "AppRole created on local Vault"
    return 0
  else
    log_error "AppRole creation failed"
    audit_entry "vault_create_approle" "failed" "AppRole creation error"
    return 1
  fi
}

execute_gcp_option_c() {
  log_info "Executing GCP Option C: Enable Cloud-Audit compliance module"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would execute:"
    log_info "  bash scripts/ops/OPERATOR_ENABLE_COMPLIANCE_MODULE.sh --gcp-project $GCP_PROJECT"
    audit_entry "gcp_compliance_enable" "dry-run" "Option C: enable compliance"
    return 0
  fi
  
  if bash "$SCRIPT_DIR/ops/OPERATOR_ENABLE_COMPLIANCE_MODULE.sh" \
         --gcp-project "$GCP_PROJECT" \
         --terraform-apply \
         --immutable-audit "$AUDIT_DIR"; then
    log_success "GCP compliance module enabled"
    audit_entry "gcp_compliance_enable" "success" "Cloud-Audit compliance active"
    return 0
  else
    log_error "GCP compliance enablement failed"
    audit_entry "gcp_compliance_enable" "failed" "Compliance module error"
    return 1
  fi
}

main() {
  parse_args "$@"
  validate_inputs
  
  log_info "Phase 3B: Day-2 Operations Launcher"
  log_info "Operation ID: $OPERATION_ID"
  log_info "Vault option: $VAULT_OPTION"
  log_info "GCP option: $GCP_OPTION"
  log_info "Dry-run: $DRY_RUN"
  
  preflight_check || exit 1
  
  # Execute based on options
  case "$VAULT_OPTION:$GCP_OPTION" in
    # Full hardening paths
    a:a)
      log_info "Path: Full hardening (Vault restore + GCP compliance)"
      execute_vault_option_a && execute_gcp_option_c
      ;;
    b:a)
      log_info "Path: Full hardening (Vault create + GCP compliance)"
      execute_vault_option_b && execute_gcp_option_c
      ;;
    # Individual operations
    a:d)
      log_info "Path: Vault restore only"
      execute_vault_option_a
      ;;
    b:d)
      log_info "Path: Vault create only"
      execute_vault_option_b
      ;;
    c:c)
      log_info "Path: GCP compliance only"
      execute_gcp_option_c
      ;;
    # Minimal/skip paths
    c:d)
      log_warn "No operations selected (both skipped)"
      log_info "Phase 3 infrastructure remains operational with GSM credentials"
      audit_entry "phase3b_launch" "skipped" "No Vault or GCP operations"
      ;;
    *)
      log_error "Invalid option combination: $VAULT_OPTION:$GCP_OPTION"
      exit 1
      ;;
  esac
  
  log_success "Phase 3B operations completed"
  audit_entry "phase3b_complete" "success" "Day-2 operations finalized"
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "Audit trails: $AUDIT_DIR/audit-$OPERATION_ID.jsonl"
  echo "Next: Monitor Phase 3B operations via Grafana or journalctl"
  echo "═══════════════════════════════════════════════════════════════"
}

main "$@"
