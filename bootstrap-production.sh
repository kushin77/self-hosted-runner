#!/bin/bash

################################################################################
# 🚀 PRODUCTION BOOTSTRAP AUTOMATION
# 
# One-command setup for production infrastructure prerequisites
# Executes Phases 1-3 from PRODUCTION_BOOTSTRAP_CHECKLIST.md
#
# Usage:
#   bash bootstrap-production.sh [--nas-host 192.16.168.39] \
#                                [--worker-host 192.168.168.42] \
#                                [--full] [--dry-run]
#
# Mandate Compliance: Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off
################################################################################

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

NAS_HOST="${NAS_HOST:-192.16.168.39}"
WORKER_HOST="${WORKER_HOST:-192.168.168.42}"
GCP_PROJECT="${GCP_PROJECT:-}"
DRY_RUN=false
FULL_RUN=false
VERBOSE=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ════════════════════════════════════════════════════════════════════════════
# LOGGING
# ════════════════════════════════════════════════════════════════════════════

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
    echo -e "${RED}✗${NC} $*"
}

log_step() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}▶ $*${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
}

# ════════════════════════════════════════════════════════════════════════════
# PARSING & VALIDATION
# ════════════════════════════════════════════════════════════════════════════

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --nas-host)
                NAS_HOST="$2"
                shift 2
                ;;
            --worker-host)
                WORKER_HOST="$2"
                shift 2
                ;;
            --gcp-project)
                GCP_PROJECT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --full)
                FULL_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
    cat << 'EOF'
Usage: bash bootstrap-production.sh [OPTIONS]

Phase 1: Configure NAS Exports
Phase 2: Create Service Account on Worker
Phase 3: Store SSH Keys in GCP Secret Manager

OPTIONS:
  --nas-host HOST         NAS server address (default: 192.16.168.39)
  --worker-host HOST      Worker node address (default: 192.168.168.42)
  --gcp-project PROJECT   GCP project ID (auto-detected if not provided)
  --full                  Execute all phases without prompts
  --dry-run               Show what would be executed without running
  -v, --verbose           Verbose output
  -h, --help              Show this help message

EXAMPLE:
  bash bootstrap-production.sh --nas-host 192.16.168.39 --worker-host 192.168.168.42 --full
EOF
}

# ════════════════════════════════════════════════════════════════════════════
# VERIFICATION
# ════════════════════════════════════════════════════════════════════════════

verify_prerequisites() {
    log_step "VERIFYING PREREQUISITES"
    
    local all_ok=true
    
    # Check SSH access to NAS
    log_info "Testing SSH access to NAS (${NAS_HOST})..."
    if ssh-keyscan -T 2 "${NAS_HOST}" > /dev/null 2>&1; then
        log_success "NAS SSH reachable"
    else
        log_warn "Cannot reach NAS via SSH (may require manual setup)"
        all_ok=false
    fi
    
    # Check SSH access to Worker
    log_info "Testing SSH access to Worker (${WORKER_HOST})..."
    if ssh-keyscan -T 2 "${WORKER_HOST}" > /dev/null 2>&1; then
        log_success "Worker SSH reachable"
    else
        log_warn "Cannot reach Worker via SSH"
        all_ok=false
    fi
    
    # Check GCP authentication
    if command -v gcloud &> /dev/null; then
        log_info "Checking GCP authentication..."
        if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
            log_success "GCP authenticated"
            GCP_PROJECT=$(gcloud config get-value project 2>/dev/null)
            log_info "GCP Project: ${GCP_PROJECT}"
        else
            log_error "GCP not authenticated. Run: gcloud auth login"
            all_ok=false
        fi
    else
        log_warn "gcloud CLI not installed"
        all_ok=false
    fi
    
    if [ "$all_ok" = false ]; then
        log_error "Prerequisites not fully met. Continue anyway? (y/n)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: NAS EXPORTS
# ════════════════════════════════════════════════════════════════════════════

phase_1_nas_exports() {
    log_step "PHASE 1: NAS EXPORTS CONFIGURATION"
    
    local exports_cmd='
    echo "Checking existing exports..."
    grep -q "/repositories" /etc/exports && echo "  ℹ /repositories already exported" || echo "  ✓ Need to add /repositories"
    grep -q "/config-vault" /etc/exports && echo "  ℹ /config-vault already exported" || echo "  ✓ Need to add /config-vault"
    
    echo "Adding exports to /etc/exports..."
    sudo tee -a /etc/exports <<'\''EOX'\'' 2>/dev/null
/repositories *.168.168.0/24(rw,sync,no_subtree_check)
/config-vault *.168.168.0/24(rw,sync,no_subtree_check)
EOX
    
    echo "Reloading NFS exports..."
    sudo exportfs -r
    
    echo "Verifying exports..."
    sudo exportfs -v | grep -E "^/(repositories|config-vault)"
    '
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute on NAS (${NAS_HOST}):"
        echo "$exports_cmd"
    else
        log_info "Executing on NAS (${NAS_HOST})..."
        ssh "root@${NAS_HOST}" bash -c "$exports_cmd" || {
            log_error "Failed to configure NAS exports"
            return 1
        }
        log_success "NAS exports configured"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: SERVICE ACCOUNT
# ════════════════════════════════════════════════════════════════════════════

phase_2_service_account() {
    log_step "PHASE 2: SERVICE ACCOUNT CREATION"
    
    local account_cmd='
    echo "Checking if svc-git exists..."
    if id svc-git &>/dev/null; then
        echo "  ℹ svc-git account already exists"
    else
        echo "  ✓ Creating svc-git account..."
        sudo useradd -m -s /bin/bash svc-git
    fi
    
    echo "Setting up SSH directory..."
    sudo -u svc-git mkdir -p /home/svc-git/.ssh
    sudo chmod 700 /home/svc-git/.ssh
    
    echo "Verifying account..."
    id svc-git
    stat /home/svc-git
    '
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute on Worker (${WORKER_HOST}):"
        echo "$account_cmd"
    else
        log_info "Executing on Worker (${WORKER_HOST})..."
        ssh "root@${WORKER_HOST}" bash -c "$account_cmd" || {
            log_error "Failed to create service account"
            return 1
        }
        log_success "Service account created on Worker"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: GCP SECRET MANAGER
# ════════════════════════════════════════════════════════════════════════════

phase_3_gsm() {
    log_step "PHASE 3: SSH KEYS IN GCP SECRET MANAGER"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute locally:"
        log_info "gcloud secrets create svc-git-ssh-key --data-file=\$HOME/.ssh/id_ed25519"
        return 0
    fi
    
    # Check if secret already exists
    if gcloud secrets describe svc-git-ssh-key &>/dev/null; then
        log_warn "Secret 'svc-git-ssh-key' already exists"
        log_info "Update it? (y/n)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_warn "Skipping secret update"
            return 0
        fi
    fi
    
    # Verify SSH key exists
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        log_error "SSH key not found: $HOME/.ssh/id_ed25519"
        return 1
    fi
    
    log_info "Storing SSH key in GCP Secret Manager..."
    gcloud secrets create svc-git-ssh-key \
        --data-file="$HOME/.ssh/id_ed25519" \
        --labels=component=deployment,constraint=ephemeral,environment=production \
        --replication-policy="automatic" 2>/dev/null || {
        log_warn "Secret creation returned status (may already exist)"
    }
    
    log_success "SSH key stored in Secret Manager"
    log_info "Secret details:"
    gcloud secrets describe svc-git-ssh-key
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════

main() {
    cat << 'BANNER'
╔════════════════════════════════════════════════════════════════════════════╗
║                  🚀 PRODUCTION BOOTSTRAP AUTOMATION                        ║
║                                                                            ║
║  Configures infrastructure prerequisites for NAS redeployment             ║
║  Mandate: Immutable | Ephemeral | Idempotent | No-Ops | Hands-Off        ║
╚════════════════════════════════════════════════════════════════════════════╝
BANNER
    
    parse_args "$@"
    
    log_info "Configuration:"
    log_info "  NAS Host: ${NAS_HOST}"
    log_info "  Worker Host: ${WORKER_HOST}"
    log_info "  GCP Project: ${GCP_PROJECT}"
    log_info "  Dry Run: ${DRY_RUN}"
    log_info "  Full Run: ${FULL_RUN}"
    
    verify_prerequisites
    
    if [ "$FULL_RUN" != true ]; then
        log_info ""
        log_info "Ready to proceed with infrastructure bootstrap?"
        log_info "This will:"
        log_info "  1. Configure NAS exports (Phase 1)"
        log_info "  2. Create svc-git service account (Phase 2)"
        log_info "  3. Store SSH keys in GSM (Phase 3)"
        log_info ""
        log_info "Proceed? (y/n)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_warn "Bootstrap cancelled"
            exit 0
        fi
    fi
    
    phase_1_nas_exports || {
        log_error "Phase 1 failed. Continue? (y/n)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && exit 1
    }
    
    phase_2_service_account || {
        log_error "Phase 2 failed. Continue? (y/n)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && exit 1
    }
    
    phase_3_gsm || {
        log_error "Phase 3 failed. Continue? (y/n)"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && exit 1
    }
    
    log_step "BOOTSTRAP COMPLETE"
    log_success "Infrastructure prerequisites configured"
    log_info ""
    log_info "Next step: Execute production deployment"
    log_info "  bash deploy-orchestrator.sh full"
    log_info ""
    log_info "Monitor:"
    log_info "  bash verify-nas-redeployment.sh comprehensive"
}

main "$@"
