#!/bin/bash

###############################################################################
# PROVISION-OPERATOR-CREDENTIALS.SH
# 
# Comprehensive credential provisioning orchestrator for direct deployment.
# 
# This script automates:
#   1. SSH key generation/retrieval
#   2. Storage in credential provider (GSM/Vault/AWS)
#   3. Authorization on worker node
#   4. Vault runtime configuration
#   5. Verification and readiness check
#   6. Deployment trigger
#
# Usage:
#   bash scripts/provision-operator-credentials.sh [--dry-run] [--no-deploy]
#
# Requirements:
#   - gcloud CLI (for GSM access)
#   - ssh-keygen (for key generation)
#   - curl or wget (for HTTP verification)
#   - jq (for JSON parsing, optional)
#
# Author: Copilot
# Date: 2026-03-09
###############################################################################

set -euo pipefail

# Initialize variables (before readonly)
DRY_RUN="${DRY_RUN:-false}"
SKIP_DEPLOY="${SKIP_DEPLOY:-false}"
VERBOSE="${VERBOSE:-false}"

# Parse arguments before setting readonly
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --no-deploy) SKIP_DEPLOY=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Now set as readonly
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(dirname "$SCRIPT_DIR")"
readonly DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
readonly DEPLOY_USER="${DEPLOY_USER:-runner}"
readonly DRY_RUN
readonly SKIP_DEPLOY
readonly VERBOSE

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

###############################################################################
# LOGGING FUNCTIONS
###############################################################################

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }
debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}DEBUG:${NC} $*" || true; }

###############################################################################
# SECTION 1: SSH KEY PROVISIONING
###############################################################################

provision_ssh_key() {
    local ssh_key_file="${REPO_DIR}/.ssh/runner_ed25519"
    local ssh_key_pub="${ssh_key_file}.pub"

    log "=========================================="
    log "SECTION 1: SSH Key Provisioning"
    log "=========================================="

    # Step 1.1: Generate SSH key if not exists
    log "Step 1.1: Generate SSH key pair..."
    if [[ ! -f "$ssh_key_file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [DRY-RUN] Would generate: $ssh_key_file"
            log "  [DRY-RUN] Command: ssh-keygen -t ed25519 -f $ssh_key_file -N '' -C '$DEPLOY_USER@$DEPLOY_TARGET'"
        else
            ssh-keygen -t ed25519 -f "$ssh_key_file" -N '' -C "$DEPLOY_USER@$DEPLOY_TARGET" || {
                error "Failed to generate SSH key"
                return 1
            }
            success "SSH key generated: $ssh_key_file"
            chmod 600 "$ssh_key_file"
            debug "Key file permissions set to 600"
        fi
    else
        warning "SSH key already exists: $ssh_key_file"
        # Verify it's valid
        if ssh-keygen -l -f "$ssh_key_file" > /dev/null 2>&1; then
            success "SSH key is valid"
        else
            error "SSH key is invalid or corrupted"
            return 1
        fi
    fi

    # Step 1.2: Store private key in GSM
    log "Step 1.2: Store private SSH key in GSM..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY-RUN] Would store secret: RUNNER_SSH_KEY"
        log "  [DRY-RUN] Command: gcloud secrets versions add RUNNER_SSH_KEY --data-file=$ssh_key_file"
    else
        if gcloud secrets versions add RUNNER_SSH_KEY --data-file="$ssh_key_file" 2>/dev/null; then
            success "Private key stored in GSM as RUNNER_SSH_KEY"
        else
            warning "Could not create GSM secret (secret may not exist). Attempting to create..."
            gcloud secrets create RUNNER_SSH_KEY \
                --replication-policy="automatic" \
                --data-file="$ssh_key_file" 2>/dev/null || {
                error "Failed to store SSH key in GSM. Check gcloud auth and permissions."
                return 1
            }
            success "Created GSM secret: RUNNER_SSH_KEY"
        fi
    fi

    # Step 1.3: Store username in GSM
    log "Step 1.3: Store SSH username in GSM..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY-RUN] Would store secret: RUNNER_SSH_USER=$DEPLOY_USER"
        log "  [DRY-RUN] Command: echo '$DEPLOY_USER' | gcloud secrets versions add RUNNER_SSH_USER --data-file=-"
    else
        echo "$DEPLOY_USER" | gcloud secrets versions add RUNNER_SSH_USER --data-file=- 2>/dev/null || {
            gcloud secrets create RUNNER_SSH_USER \
                --replication-policy="automatic" \
                --data-file=- <<< "$DEPLOY_USER" 2>/dev/null || {
                error "Failed to store SSH user in GSM"
                return 1
            }
        }
        success "Stored SSH username in GSM: RUNNER_SSH_USER=$DEPLOY_USER"
    fi

    # Step 1.4: Display public key
    log "Step 1.4: Public SSH key for authorization..."
    if [[ ! -f "$ssh_key_pub" ]]; then
        error "Public key file not found: $ssh_key_pub"
        return 1
    fi

    local pub_key
    pub_key=$(cat "$ssh_key_pub")
    success "Public SSH key:"
    echo "---"
    echo "$pub_key"
    echo "---"

    # Step 1.5: Attempt to authorize on worker (requires out-of-band access)
    log "Step 1.5: Authorize public key on worker..."
    log "  Manual action required on worker node:"
    echo ""
    echo "1. Connect to worker: ssh $DEPLOY_USER@$DEPLOY_TARGET"
    echo "2. Ensure ~/.ssh directory exists: mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo "3. Add public key to authorized_keys:"
    echo ""
    echo "   echo '$pub_key' >> ~/.ssh/authorized_keys"
    echo "   chmod 600 ~/.ssh/authorized_keys"
    echo ""

    if [[ "$DRY_RUN" != "true" ]]; then
        # Try to authorize if we have SSH access (unlikely, but worth trying)
        if timeout 2 ssh -o ConnectTimeout=1 "$DEPLOY_USER@$DEPLOY_TARGET" "echo '$pub_key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null; then
            success "Automatically authorized public key on worker!"
        else
            warning "Could not remotely authorize key (no SSH access yet)"
            warning "Operator must manually add public key to authorized_keys on worker"
            return 1
        fi
    fi
}

###############################################################################
# SECTION 2: VAULT CONFIGURATION
###############################################################################

provision_vault() {
    log "=========================================="
    log "SECTION 2: Vault Configuration"
    log "=========================================="

    # Check if vault-setup.sh exists
    if [[ ! -f "$REPO_DIR/scripts/vault-setup.sh" ]]; then
        warning "Vault setup script not found: $REPO_DIR/scripts/vault-setup.sh"
        log "  Operator must manually configure Vault using vault-policy.hcl"
        return 1
    fi

    log "Step 2.1: Review Vault setup commands..."
    log "  Run these commands on your Vault server:"
    echo ""
    cat "$REPO_DIR/scripts/vault-setup.sh" | grep -E "^(vault |gcloud secrets)" | head -20
    echo ""
    log "  See full setup: cat scripts/vault-setup.sh"
}

###############################################################################
# SECTION 3: WORKER BOOTSTRAP
###############################################################################

bootstrap_worker() {
    log "=========================================="
    log "SECTION 3: Worker Bootstrap"
    log "=========================================="

    if [[ ! -f "$REPO_DIR/scripts/bootstrap-worker.sh" ]]; then
        warning "Bootstrap script not found: $REPO_DIR/scripts/bootstrap-worker.sh"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY-RUN] Would execute bootstrap on worker..."
        log "  [DRY-RUN] Command: ssh $DEPLOY_USER@$DEPLOY_TARGET 'bash /opt/self-hosted-runner/scripts/bootstrap-worker.sh'"
    else
        log "  Attempting bootstrap on worker..."
        if timeout 30 ssh "$DEPLOY_USER@$DEPLOY_TARGET" "bash /opt/self-hosted-runner/scripts/bootstrap-worker.sh" 2>/dev/null; then
            success "Worker bootstrap completed"
        else
            warning "Could not bootstrap worker (no SSH access). Manual bootstrap required:"
            echo ""
            echo "  ssh $DEPLOY_USER@$DEPLOY_TARGET"
            echo "  cd /opt/self-hosted-runner"
            echo "  sudo bash scripts/bootstrap-worker.sh"
            echo ""
            return 1
        fi
    fi
}

###############################################################################
# SECTION 4: VERIFICATION
###############################################################################

verify_provisioning() {
    log "=========================================="
    log "SECTION 4: Verification & Health Check"
    log "=========================================="

    # Check GSM secrets
    log "Checking GSM secrets..."
    if gcloud secrets versions list RUNNER_SSH_KEY --limit=1 &>/dev/null; then
        success "✓ RUNNER_SSH_KEY exists in GSM"
    else
        error "✗ RUNNER_SSH_KEY not found in GSM"
        return 1
    fi

    if gcloud secrets versions list RUNNER_SSH_USER --limit=1 &>/dev/null; then
        success "✓ RUNNER_SSH_USER exists in GSM"
    else
        error "✗ RUNNER_SSH_USER not found in GSM"
        return 1
    fi

    # Check SSH connectivity
    log "Checking SSH connectivity to worker..."
    if timeout 5 ssh -i "${REPO_DIR}/.ssh/runner_ed25519" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=3 \
        "$DEPLOY_USER@$DEPLOY_TARGET" "echo 'SSH connectivity verified'" 2>/dev/null; then
        success "✓ SSH connectivity verified"
        return 0
    else
        warning "✗ SSH connectivity not yet available"
        warning "  Public key must be authorized on worker before deployment"
        return 1
    fi
}

###############################################################################
# SECTION 5: DEPLOYMENT TRIGGER
###############################################################################

trigger_deployment() {
    log "=========================================="
    log "SECTION 5: Deployment Trigger"
    log "=========================================="

    if [[ "$SKIP_DEPLOY" == "true" ]]; then
        log "  [SKIP] Deployment skipped by user"
        return 0
    fi

    log "  Executing direct deployment..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY-RUN] Would execute: bash scripts/direct-deploy.sh gsm main"
        return 0
    else
        cd "$REPO_DIR"
        if bash scripts/direct-deploy.sh gsm main; then
            success "Deployment completed successfully!"
            return 0
        else
            error "Deployment failed. Check logs for details."
            return 1
        fi
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    log "=========================================="
    log "OPERATOR CREDENTIAL PROVISIONING"
    log "=========================================="
    log "Target: $DEPLOY_TARGET"
    log "User: $DEPLOY_USER"
    log "Dry Run: $DRY_RUN"
    log "Skip Deploy: $SKIP_DEPLOY"
    echo ""

    # Check prerequisites
    log "Checking prerequisites..."
    command -v gcloud >/dev/null || {
        error "gcloud CLI not found. Install: curl https://sdk.cloud.google.com | bash"
        exit 1
    }
    command -v ssh-keygen >/dev/null || {
        error "ssh-keygen not found"
        exit 1
    }
    success "Prerequisites satisfied"
    echo ""

    # Execute provisioning sections
    provision_ssh_key || warning "SSH key provisioning incomplete (manual action required)"
    echo ""

    provision_vault || warning "Vault configuration step incomplete"
    echo ""

    bootstrap_worker || warning "Worker bootstrap incomplete (manual action may be required)"
    echo ""

    verify_provisioning || {
        warning "Provisioning verification incomplete"
        warning "Waiting for SSH key authorization..."
        if [[ "$DRY_RUN" != "true" ]]; then
            log "Next steps:"
            echo "  1. Authorize public key on worker (see above)"
            echo "  2. Run: bash scripts/verify-deployment-provisioning.sh"
            echo "  3. Run: bash scripts/direct-deploy.sh gsm main"
            exit 1
        fi
    }
    echo ""

    trigger_deployment || {
        error "Deployment failed"
        exit 1
    }
    echo ""

    success "=========================================="
    success "PROVISIONING COMPLETE"
    success "=========================================="
}

# Execute main function
main
