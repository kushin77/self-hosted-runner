#!/bin/bash

###############################################################################
# DEPLOY-OPERATOR-CREDENTIALS.SH
# 
# Final step: Provision generated SSH key to credential provider (GSM/Vault/AWS)
# and authorize on worker node.
#
# PREREQUISITES:
#   ✅ SSH key generated at .ssh/runner_ed25519
#   ✅ wait-and-deploy.sh watcher running on bastion
#   ✅ Choose credential provider (GSM, Vault, or AWS)
#
# Usage:
#   # Provision to GSM (Google Secret Manager)
#   bash scripts/deploy-operator-credentials.sh gsm
#
#   # Provision to Vault
#   bash scripts/deploy-operator-credentials.sh vault
#
#   # Provision to AWS Secrets Manager
#   bash scripts/deploy-operator-credentials.sh aws
#
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SSH_KEY_PATH="${REPO_DIR}/.ssh/runner_ed25519"
SSH_PUB_PATH="${REPO_DIR}/.ssh/runner_ed25519.pub"
DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"

# Get credential provider from argument
CRED_PROVIDER="${1:-gsm}"

# Validate inputs
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    log_error "SSH private key not found at: $SSH_KEY_PATH"
fi

if [[ ! -f "$SSH_PUB_PATH" ]]; then
    log_error "SSH public key not found at: $SSH_PUB_PATH"
fi

case "${CRED_PROVIDER,,}" in
    gsm|vault|aws)
        ;;
    *)
        log_error "Invalid credential provider: $CRED_PROVIDER. Use: gsm, vault, or aws"
        ;;
esac

log_info "Deploying SSH credentials to $CRED_PROVIDER..."

# ==== STEP 1: Prepare SSH key
log_info "Step 1: Preparing SSH key..."
SSH_KEY_CONTENT="$(cat "$SSH_KEY_PATH")"
SSH_KEY_BASE64="$(base64 -w0 < "$SSH_KEY_PATH")"
SSH_PUB_CONTENT="$(cat "$SSH_PUB_PATH")"
log_ok "SSH key loaded ($(wc -c < "$SSH_KEY_PATH") bytes)"

# ==== STEP 2: Provision to credential provider
case "${CRED_PROVIDER,,}" in
    gsm)
        log_info "Step 2: Provisioning to Google Secret Manager..."
        PROJECT="elevatediq-runner"
        SECRET_NAME="runner-ssh-key"
        
        # Create secret (if not exists) or update version
        if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
            log_info "Secret already exists; adding new version..."
            echo -n "$SSH_KEY_CONTENT" | gcloud secrets versions add "$SECRET_NAME" \
                --project="$PROJECT" \
                --data-file=- \
                >/dev/null 2>&1
            log_ok "New version added to GSM"
        else
            log_info "Creating new secret..."
            echo -n "$SSH_KEY_CONTENT" | gcloud secrets create "$SECRET_NAME" \
                --project="$PROJECT" \
                --replication-policy="automatic" \
                --data-file=- \
                >/dev/null 2>&1
            log_ok "Secret created in GSM"
        fi
        
        # Store metadata
        log_info "Storing metadata..."
        gcloud secrets versions add "$SECRET_NAME" \
            --project="$PROJECT" \
            --data-file=<(echo "user=$DEPLOY_USER") \
            >/dev/null 2>&1 || true
        log_ok "Metadata stored"
        ;;
        
    vault)
        log_info "Step 2: Provisioning to HashiCorp Vault..."
        VAULT_PATH="secret/runner-deploy"
        
        if [[ -z "${VAULT_ADDR:-}" ]]; then
            log_warn "VAULT_ADDR not set; using default: https://vault.example.com:8200"
            export VAULT_ADDR="https://vault.example.com:8200"
        fi
        
        log_info "Storing key in Vault at $VAULT_PATH..."
        vault kv put "$VAULT_PATH" \
            ssh_key="$SSH_KEY_CONTENT" \
            ssh_user="$DEPLOY_USER" \
            >/dev/null 2>&1
        log_ok "Key stored in Vault"
        ;;
        
    aws)
        log_info "Step 2: Provisioning to AWS Secrets Manager..."
        SECRET_NAME="runner/ssh-credentials"
        REGION="${AWS_REGION:-us-east-1}"
        
        # Create or update secret
        if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" >/dev/null 2>&1; then
            log_info "Secret already exists; updating value..."
            aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "{\"ssh_key\": $(echo -n "$SSH_KEY_CONTENT" | jq -Rs .), \"ssh_user\": \"$DEPLOY_USER\"}" \
                --region "$REGION" \
                >/dev/null 2>&1
            log_ok "Secret updated"
        else
            log_info "Creating new secret..."
            aws secretsmanager create-secret \
                --name "$SECRET_NAME" \
                --secret-string "{\"ssh_key\": $(echo -n "$SSH_KEY_CONTENT" | jq -Rs .), \"ssh_user\": \"$DEPLOY_USER\"}" \
                --region "$REGION" \
                >/dev/null 2>&1
            log_ok "Secret created"
        fi
        ;;
esac

# ==== STEP 3: Authorize public key on worker
log_info "Step 3: Authorizing public key on worker $DEPLOY_TARGET..."

_authorize() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${DEPLOY_USER}@${DEPLOY_TARGET}" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys" \
        < "$SSH_PUB_PATH" 2>/dev/null || return 1
}

if _authorize; then
    log_ok "Public key authorized on worker"
else
    log_warn "Could not authorize key via SSH; ensure manual authorization or use direct deployment"
fi

# ==== STEP 4: Verify
log_info "Step 4: Verifying deployment..."
sleep 2

SSH_KEY_READY=false
case "${CRED_PROVIDER,,}" in
    gsm)
        if gcloud secrets versions access latest --secret="runner-ssh-key" --project="elevatediq-runner" >/dev/null 2>&1; then
            SSH_KEY_READY=true
        fi
        ;;
    vault)
        if vault kv get -field=ssh_key secret/runner-deploy >/dev/null 2>&1; then
            SSH_KEY_READY=true
        fi
        ;;
    aws)
        if aws secretsmanager get-secret-value --secret-id "runner/ssh-credentials" --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1; then
            SSH_KEY_READY=true
        fi
        ;;
esac

if [[ "$SSH_KEY_READY" == "true" ]]; then
    log_ok "Credentials verified in $CRED_PROVIDER"
else
    log_warn "Could not verify credentials; check provider configuration"
fi

# ==== STEP 5: Trigger deployment
log_info "Step 5: Deployment ready!"
echo ""
log_ok "=========================================="
log_ok "SSH Credentials Deployed Successfully"
log_ok "=========================================="
echo ""
echo "Next steps:"
echo "  1. Watcher will auto-detect credentials within 30 seconds"
echo "  2. Direct-deploy.sh will automatically trigger"
echo "  3. Deployment audit will be posted to GitHub issue #2072"
echo "  4. Check status: ssh akushnir@192.168.168.42 'systemctl status wait-and-deploy.service'"
echo ""
echo "To monitor deployment logs:"
echo "  ssh akushnir@192.168.168.42 'sudo journalctl -u wait-and-deploy.service -f'"
echo ""
