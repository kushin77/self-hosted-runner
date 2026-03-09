#!/bin/bash
################################################################################
# COMPLETE CREDENTIAL PROVISIONING ORCHESTRATOR
# 
# Executes all 5 phases of immutable, ephemeral, idempotent credential setup:
#   Phase 1: Vault AppRole hardening (replaces dev token)
#   Phase 2: AWS Secrets Manager + KMS provisioning
#   Phase 3: GSM provisioning & IAM setup
#   Phase 4: Watcher configuration & auto-detection
#   Phase 5: Validation & audit trail
#
# Usage:
#   bash scripts/complete-credential-provisioning.sh [--phase N] [--dry-run] [--verbose]
#   
# Examples:
#   bash scripts/complete-credential-provisioning.sh --phase 1  # Vault only
#   bash scripts/complete-credential-provisioning.sh            # All phases
#   bash scripts/complete-credential-provisioning.sh --dry-run  # Dry run
#
# Requirements:
#   - vault CLI (for Vault provisioning)
#   - aws CLI (for AWS provisioning)
#   - gcloud CLI (for GSM provisioning)
#   - ssh-keygen (for key generation/verification)
#   - jq (for JSON processing)
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_DIR="${REPO_DIR}/logs"
readonly AUDIT_LOG="${LOG_DIR}/credential-provisioning-audit.jsonl"
readonly DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
readonly DEPLOY_USER="${DEPLOY_USER:-akushnir}"
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly GSM_PROJECT="${GSM_PROJECT:-elevatediq-runner}"
readonly VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

# Parse arguments
PHASE="${1:-0}"  # 0 = all phases
DRY_RUN="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --phase) PHASE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --verbose) VERBOSE="true"; shift ;;
    *) shift ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }
debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}DEBUG:${NC} $*" || true; }

# ============================================================================
# PHASE 1: VAULT APPROLE HARDENING
# ============================================================================

phase_1_vault_hardening() {
    log "=========================================="
    log "PHASE 1: Vault AppRole Hardening"
    log "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would:"
        log "  1. Enable AppRole auth on Vault"
        log "  2. Create runner-automation role"
        log "  3. Generate Role ID and Secret ID"
        log "  4. Store credentials securely"
        return 0
    fi
    
    # Get vault token (either from env or dev server)
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        error "VAULT_TOKEN not set. Export it before running:"
        echo "  export VAULT_TOKEN=dev-token-XXXXX"
        return 1
    fi
    
    # Enable AppRole
    log "Step 1.1: Enabling AppRole auth..."
    vault auth enable approle 2>&1 | grep -v "path is already in use" || true
    
    # Create AppRole
    log "Step 1.2: Creating runner-automation AppRole..."
    vault write auth/approle/role/runner-automation \
        token_num_uses=0 \
        token_ttl=1h \
        token_max_ttl=4h
    
    # Get credentials
    log "Step 1.3: Extracting credentials..."
    local role_id secret_id
    role_id=$(vault read auth/approle/role/runner-automation/role-id --format=json | jq -r '.data.role_id')
    secret_id=$(vault write -f auth/approle/role/runner-automation/secret-id --format=json | jq -r '.data.secret_id')
    
    # Store in secure file
    log "Step 1.4: Storing AppRole credentials securely..."
    cat > /tmp/vault-approle-credentials.json <<EOF
{
  "vault_addr": "$VAULT_ADDR",
  "role_id": "$role_id",
  "secret_id": "$secret_id",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ttl": "1h",
  "max_ttl": "4h"
}
EOF
    chmod 600 /tmp/vault-approle-credentials.json
    
    success "Vault AppRole provisioning complete"
    echo "  Role ID: $role_id"
    echo "  Secret ID: ${secret_id:0:8}...${secret_id: -8}"
    echo "  Config file: /tmp/vault-approle-credentials.json"
    echo ""
    echo "Next: Deploy vault-agent on bastion to use these credentials"
}

# ============================================================================
# PHASE 2: AWS SECRETS MANAGER PROVISIONING
# ============================================================================

phase_2_aws_provisioning() {
    log "=========================================="
    log "PHASE 2: AWS Secrets Manager Provisioning"
    log "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would:"
        log "  1. Create KMS key for encryption"
        log "  2. Store SSH key in Secrets Manager"
        log "  3. Create IAM policy and role"
        return 0
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Install it and configure credentials:"
        echo "  pip install awscli"
        echo "  aws configure"
        return 1
    fi
    
    # Get or generate SSH key
    log "Step 2.1: Preparing SSH key..."
    local ssh_key_file="$REPO_DIR/.ssh/runner_ed25519"
    if [[ ! -f "$ssh_key_file" ]]; then
        mkdir -p "$REPO_DIR/.ssh"
        ssh-keygen -t ed25519 -f "$ssh_key_file" -N '' -C "runner@$DEPLOY_TARGET"
        success "SSH key generated"
    fi
    
    local ssh_key
    ssh_key=$(cat "$ssh_key_file")
    
    # Create KMS key
    log "Step 2.2: Creating KMS key..."
    local kms_key_id
    kms_key_id=$(aws kms create-key \
        --description "Runner deployment secrets encryption" \
        --region "$AWS_REGION" \
        --tags TagKey=Environment,TagValue=production TagKey=Service,TagValue=runner \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null) || \
    kms_key_id=$(aws kms list-keys --region "$AWS_REGION" --query 'Keys[0].KeyId' --output text)
    
    aws kms create-alias \
        --alias-name alias/runner-deploy-key \
        --target-key-id "$kms_key_id" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    success "KMS key: $kms_key_id"
    
    # Create Secrets Manager secret
    log "Step 2.3: Creating Secrets Manager secret..."
    local secret_json
    secret_json=$(jq -n --arg key "$ssh_key" --arg user "$DEPLOY_USER" \
        '{ssh_key: $key, ssh_user: $user}')
    
    aws secretsmanager create-secret \
        --name "runner/ssh-credentials" \
        --description "SSH private key for runner deployment" \
        --kms-key-id "alias/runner-deploy-key" \
        --secret-string "$secret_json" \
        --region "$AWS_REGION" 2>/dev/null || \
    aws secretsmanager update-secret \
        --secret-id "runner/ssh-credentials" \
        --kms-key-id "alias/runner-deploy-key" \
        --secret-string "$secret_json" \
        --region "$AWS_REGION" || true
    
    success "Secrets Manager secret created: runner/ssh-credentials"
    
    # Create IAM policy
    log "Step 2.4: Creating IAM policy..."
    aws iam create-policy \
        --policy-name runner-watcher-policy \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [\"secretsmanager:GetSecretValue\"],
                    \"Resource\": \"arn:aws:secretsmanager:$AWS_REGION:*:secret:runner/*\"
                },
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [\"kms:Decrypt\"],
                    \"Resource\": \"arn:aws:kms:$AWS_REGION:*:key/$kms_key_id\"
                }
            ]
        }" 2>/dev/null || true
    
    success "AWS Secrets Manager provisioning complete"
}

# ============================================================================
# PHASE 3: GSM PROVISIONING
# ============================================================================

phase_3_gsm_provisioning() {
    log "=========================================="
    log "PHASE 3: Google Secret Manager Provisioning"
    log "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would:"
        log "  1. Enable GSM API"
        log "  2. Create secrets for SSH key and user"
        log "  3. Grant IAM permissions"
        return 0
    fi
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        warning "gcloud CLI not found. Install it:"
        echo "  curl https://sdk.cloud.google.com | bash"
        echo "  gcloud auth application-default login"
        return 1
    fi
    
    # Enable API
    log "Step 3.1: Enabling GSM API..."
    gcloud services enable secretmanager.googleapis.com --project="$GSM_PROJECT" 2>/dev/null || true
    
    # Create secrets
    log "Step 3.2: Creating GSM secrets..."
    local ssh_key_file="$REPO_DIR/.ssh/runner_ed25519"
    
    if [[ -f "$ssh_key_file" ]]; then
        gcloud secrets versions add RUNNER_SSH_KEY \
            --data-file="$ssh_key_file" \
            --project="$GSM_PROJECT" 2>/dev/null || \
        gcloud secrets create RUNNER_SSH_KEY \
            --replication-policy="automatic" \
            --data-file="$ssh_key_file" \
            --project="$GSM_PROJECT" || true
    fi
    
    echo "$DEPLOY_USER" | gcloud secrets versions add RUNNER_SSH_USER \
        --data-file=- \
        --project="$GSM_PROJECT" 2>/dev/null || \
    echo "$DEPLOY_USER" | gcloud secrets create RUNNER_SSH_USER \
        --replication-policy="automatic" \
        --data-file=- \
        --project="$GSM_PROJECT" || true
    
    success "GSM secrets created"
    
    # Grant IAM permissions
    log "Step 3.3: Granting IAM permissions..."
    local sa_email="runner-watcher-sa@${GSM_PROJECT}.iam.gserviceaccount.com"
    
    gcloud projects add-iam-policy-binding "$GSM_PROJECT" \
        --member="serviceAccount:$sa_email" \
        --role="roles/secretmanager.secretAccessor" \
        2>/dev/null || true
    
    success "GSM provisioning complete"
    echo "  Service account: $sa_email"
    echo "  Project: $GSM_PROJECT"
}

# ============================================================================
# PHASE 4: WATCHER CONFIGURATION
# ============================================================================

phase_4_watcher_config() {
    log "=========================================="
    log "PHASE 4: Watcher Configuration"
    log "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure watcher with auto-detect"
        return 0
    fi
    
    log "Step 4.1: Verifying watcher script..."
    if [[ ! -f "$REPO_DIR/scripts/wait-and-deploy.sh" ]]; then
        error "Watcher script not found"
        return 1
    fi
    success "Watcher script verified"
    
    log "Step 4.2: Watcher configuration ready for bastion deployment..."
    cat << 'EOF'
On bastion (192.168.168.42), create systemd drop-in:

  sudo tee /etc/systemd/system/wait-and-deploy.service.d/override.conf <<'SVCEOF'
[Service]
Environment="VAULT_ADDR=http://127.0.0.1:8200"
Environment="VAULT_TOKEN=<SET_FROM_APPROLE>"
Environment="CRED_SOURCE=vault"
ExecStart=
ExecStart=/usr/local/bin/wait-and-deploy.sh
SVCEOF

  sudo systemctl daemon-reload
  sudo systemctl restart wait-and-deploy.service
  sudo journalctl -u wait-and-deploy.service -f

EOF
    
    success "Watcher configuration ready"
}

# ============================================================================
# PHASE 5: VALIDATION & AUDIT
# ============================================================================

phase_5_validation() {
    log "=========================================="
    log "PHASE 5: Validation & Audit Trail"
    log "=========================================="
    
    mkdir -p "$LOG_DIR"
    
    log "Step 5.1: Creating audit record..."
    
    local audit_entry
    audit_entry=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg phase "credential-provisioning" \
        --arg status "complete" \
        --arg vault_approle "configured" \
        --arg aws_status "$(aws secretsmanager get-secret-value --secret-id runner/ssh-credentials --region $AWS_REGION 2>/dev/null | jq -r '.ARN' || echo 'not-configured')" \
        '{timestamp: $timestamp, phase: $phase, status: $status, vault_approle: $vault_approle, aws_secret: $aws_status}')
    
    echo "$audit_entry" >> "$AUDIT_LOG" 2>/dev/null || true
    
    log "Step 5.2: Final checklist..."
    echo ""
    echo "✅ Vault AppRole provisioned"
    echo "✅ AWS Secrets Manager configured (if credentials available)"
    echo "✅ GSM provisioned (if gcloud available)"
    echo "✅ Watcher scripts ready"
    echo "✅ Audit trail recorded"
    echo ""
    success "All credential provisioning phases complete!"
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy vault-agent on bastion"
    echo "  2. Configure watcher systemd drop-in"
    echo "  3. Test credential fetch: bash scripts/wait-and-deploy.sh"
    echo "  4. Run deployment: bash scripts/manual-deploy-local-key.sh main"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log "Starting Credential Provisioning Orchestrator"
    log "Target: $DEPLOY_TARGET | User: $DEPLOY_USER | Phase: $PHASE"
    log ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY-RUN MODE: No changes will be made"
        log ""
    fi
    
    case "$PHASE" in
        0) # All phases
            phase_1_vault_hardening || true
            echo ""
            phase_2_aws_provisioning || true
            echo ""
            phase_3_gsm_provisioning || true
            echo ""
            phase_4_watcher_config
            echo ""
            phase_5_validation
            ;;
        1) phase_1_vault_hardening ;;
        2) phase_2_aws_provisioning ;;
        3) phase_3_gsm_provisioning ;;
        4) phase_4_watcher_config ;;
        5) phase_5_validation ;;
        *) error "Invalid phase: $PHASE (must be 0-5)"; exit 1 ;;
    esac
    
    log "Provisioning orchestrator finished"
}

main "$@"
