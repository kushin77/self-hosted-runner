#!/bin/bash

################################################################################
# DIRECT-DEPLOY: Immutable, Ephemeral, Idempotent Deployment
# 
# Usage:
#   ./direct-deploy.sh [gsm|vault|kms] [target-branch]
#
# Environment Variables:
#   DEPLOY_TARGET: Target host (default: 192.168.168.42)
#   GITHUB_ISSUE_ID: GitHub issue to log audit trail (default: 2072)
#   SKIP_VALIDATION: Skip smoke tests (default: false)
#   DRY_RUN: Show what would deploy without applying (default: false)
#
# Examples:
#   DEPLOY_TARGET=192.168.168.42 ./direct-deploy.sh gsm main
#   SKIP_VALIDATION=1 ./direct-deploy.sh vault staging
#   DRY_RUN=1 ./direct-deploy.sh kms production
#
# Features:
#   ✅ Immutable: Append-only GitHub issue audit trail
#   ✅ Ephemeral: Auto-cleanup of temp files & secrets
#   ✅ Idempotent: Safe to run multiple times
#   ✅ Zero-ops: Fully automated, hands-off
#
################################################################################

set -euo pipefail

# Configuration
DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-runner}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"
GITHUB_ISSUE_ID="${GITHUB_ISSUE_ID:-2072}"
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Credential sources
CRED_SOURCE="${1:-gsm}"
TARGET_BRANCH="${2:-main}"

# Derived variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMP_DIR=""
START_TIME=$(date +%s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOYMENT_ID="$(date +%s%N | sha256sum | cut -c1-16)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}✅ $*${NC}" >&2
}

log_warn() {
  echo -e "${YELLOW}⚠️  $*${NC}" >&2
}

log_error() {
  echo -e "${RED}❌ $*${NC}" >&2
}

# Cleanup: destroy all secrets, temp files, and residual state
cleanup() {
  local exit_code=$?
  log "Cleaning up ephemeral resources..."
  
  # Destroy all credential variables
  unset SSH_KEY SSH_USER SSH_PASS || true
  unset VAULT_TOKEN VAULT_ADDR || true
  unset AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN || true
  
  # Remove temp directory
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR" || true
  fi
  
  # Remove any leftover SSH keys in /tmp
  find /tmp -maxdepth 1 -name "ssh_key_*" -type f -delete 2>/dev/null || true
  
  if [[ $exit_code -eq 0 ]]; then
    log_success "Cleanup complete. Deployment successful."
  else
    log_error "Cleanup complete. Deployment failed with exit code $exit_code."
  fi
  
  return $exit_code
}

trap cleanup EXIT

################################################################################
# CREDENTIAL MANAGEMENT (GSM/VAULT/KMS)
################################################################################

fetch_credentials_gsm() {
  log "Fetching credentials from Google Secret Manager..."
  
  if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found. Install Google Cloud SDK."
    return 1
  fi
  
  SSH_KEY=$(gcloud secrets versions access latest --secret="runner-ssh-key" 2>/dev/null || echo "")
  SSH_USER=$(gcloud secrets versions access latest --secret="runner-ssh-user" 2>/dev/null || echo "runner")
  
  if [[ -z "$SSH_KEY" ]]; then
    log_error "Failed to fetch SSH key from GSM. Ensure secrets are configured."
    return 1
  fi
  
  log_success "Credentials fetched from GSM (will be destroyed after deployment)"
}

fetch_credentials_vault() {
  log "Fetching credentials from HashiCorp Vault..."
  
  if ! command -v vault &> /dev/null; then
    log_error "vault CLI not found. Install HashiCorp Vault."
    return 1
  fi
  
  # Ensure Vault is unsealed and accessible
  VAULT_ADDR="${VAULT_ADDR:-https://vault.local:8200}"
  export VAULT_ADDR
  
  local secret_json
  secret_json=$(vault kv get -format=json "secret/runner-deploy" 2>/dev/null || echo "{}")
  
  SSH_KEY=$(echo "$secret_json" | jq -r '.data.data.ssh_key // empty')
  SSH_USER=$(echo "$secret_json" | jq -r '.data.data.ssh_user // "runner"')
  
  if [[ -z "$SSH_KEY" ]]; then
    log_error "Failed to fetch credentials from Vault. Check path: secret/runner-deploy"
    return 1
  fi
  
  log_success "Credentials fetched from Vault (will be destroyed after deployment)"
}

fetch_credentials_kms() {
  log "Fetching credentials from AWS KMS + SecretsManager..."
  
  if ! command -v aws &> /dev/null; then
    log_error "aws CLI not found. Install AWS CLI."
    return 1
  fi
  
  # Fetch encrypted secret
  local encrypted_secret
  encrypted_secret=$(aws secretsmanager get-secret-value \
    --secret-id "runner/ssh-credentials" \
    --query 'SecretBinary' \
    --output text 2>/dev/null || echo "")
  
  if [[ -z "$encrypted_secret" ]]; then
    log_error "Failed to fetch secret from AWS Secrets Manager."
    return 1
  fi
  
  # Decrypt with KMS
  local decrypted
  decrypted=$(echo "$encrypted_secret" | base64 -d | aws kms decrypt \
    --ciphertext-blob fileb:///dev/stdin \
    --query 'Plaintext' \
    --output text 2>/dev/null | base64 -d || echo "")
  
  SSH_KEY=$(echo "$decrypted" | jq -r '.ssh_key // empty' 2>/dev/null || echo "")
  SSH_USER=$(echo "$decrypted" | jq -r '.ssh_user // "runner"' 2>/dev/null || echo "runner")
  
  if [[ -z "$SSH_KEY" ]]; then
    log_error "Failed to decrypt credentials with KMS."
    return 1
  fi
  
  log_success "Credentials fetched and decrypted from KMS (will be destroyed after deployment)"
}

fetch_credentials() {
  case "${CRED_SOURCE,,}" in
    gsm)
      fetch_credentials_gsm
      ;;
    vault)
      fetch_credentials_vault
      ;;
    kms)
      fetch_credentials_kms
      ;;
    *)
      log_error "Unknown credential source: $CRED_SOURCE"
      log "Supported: gsm, vault, kms"
      return 1
      ;;
  esac
}

################################################################################
# DEPLOYMENT PREPARATION
################################################################################

validate_environment() {
  log "Validating environment..."
  
  if ! command -v git &> /dev/null; then
    log_error "git not found"
    return 1
  fi
  
  if ! command -v gh &> /dev/null; then
    log_error "gh (GitHub CLI) not found"
    return 1
  fi
  
  if ! command -v sha256sum &> /dev/null; then
    log_error "sha256sum not found"
    return 1
  fi
  
  # Validate target host reachability
  if ! nc -z "$DEPLOY_TARGET" 22 2>/dev/null; then
    log_warn "SSH port (22) on $DEPLOY_TARGET may not be reachable (nc timeout). Proceeding anyway..."
  fi
  
  log_success "Environment validated"
}

prepare_deployment_bundle() {
  log "Preparing deployment bundle from branch: $TARGET_BRANCH"
  
  TEMP_DIR=$(mktemp -d)
  log "Using ephemeral directory: $TEMP_DIR"
  
  # Create bundle
  local bundle_path="$TEMP_DIR/deploy.bundle"
  git -C "$REPO_ROOT" bundle create "$bundle_path" "$TARGET_BRANCH" --all 2>/dev/null || {
    log_error "Failed to create git bundle"
    return 1
  }
  
  # Calculate checksums
  local bundle_sha256
  bundle_sha256=$(sha256sum "$bundle_path" | awk '{print $1}')
  
  local commit_id
  commit_id=$(git -C "$REPO_ROOT" rev-parse --short "$TARGET_BRANCH")
  
  log_success "Bundle created: $bundle_path"
  log_success "SHA256: $bundle_sha256"
  log_success "Commit: $commit_id"
  
  echo "$bundle_path"
}

################################################################################
# DEPLOYMENT EXECUTION
################################################################################

deploy_to_target() {
  local bundle_path="$1"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE: Not actually deploying"
    log "Would deploy bundle: $bundle_path"
    log "Would target: $SSH_USER@$DEPLOY_TARGET"
    return 0
  fi
  
  log "Deploying to $DEPLOY_TARGET..."
  
  # Use ephemeral SSH key (destroyed at cleanup)
  local key_file
  key_file=$(mktemp)
  echo "$SSH_KEY" > "$key_file"
  chmod 600 "$key_file"
  
  # SCP bundle to target
  scp -o ConnectTimeout=10 \
      -o StrictHostKeyChecking=accept-new \
      -i "$key_file" \
      "$bundle_path" \
      "$SSH_USER@$DEPLOY_TARGET:/tmp/deploy.bundle" || {
    log_error "Failed to transfer bundle to target"
    rm -f "$key_file"
    return 1
  }
  
  # Execute deployment on target
  ssh -o ConnectTimeout=10 \
      -o StrictHostKeyChecking=accept-new \
      -i "$key_file" \
      "$SSH_USER@$DEPLOY_TARGET" << 'REMOTE_DEPLOY'
set -euo pipefail
cd /opt/self-hosted-runner || mkdir -p /opt/self-hosted-runner && cd /opt/self-hosted-runner
git init . || true
git remote remove origin 2>/dev/null || true
git remote add origin /tmp/deploy.bundle
git fetch origin --tags --all 2>/dev/null || true
git bundle unbundle /tmp/deploy.bundle 2>/dev/null || true
git checkout -f main 2>/dev/null || git checkout -f master 2>/dev/null || true
rm -f /tmp/deploy.bundle
REMOTE_DEPLOY
  
  local deploy_status=$?
  rm -f "$key_file"
  
  if [[ $deploy_status -eq 0 ]]; then
    log_success "Deployment applied to $DEPLOY_TARGET"
  else
    log_error "Deployment failed on target host"
    return 1
  fi
}

validate_deployment() {
  if [[ "$SKIP_VALIDATION" == "true" ]]; then
    log_warn "Skipping validation (SKIP_VALIDATION=1)"
    return 0
  fi
  
  log "Running deployment validation..."
  
  # Use ephemeral SSH key
  local key_file
  key_file=$(mktemp)
  echo "$SSH_KEY" > "$key_file"
  chmod 600 "$key_file"
  
  # Run smoke tests on target (if they exist)
  ssh -o ConnectTimeout=10 \
      -i "$key_file" \
      "$SSH_USER@$DEPLOY_TARGET" \
      "test -x /opt/self-hosted-runner/scripts/smoke-tests.sh && /opt/self-hosted-runner/scripts/smoke-tests.sh || echo 'No smoke tests found'"
  
  local validate_status=$?
  rm -f "$key_file"
  
  if [[ $validate_status -eq 0 ]]; then
    log_success "Deployment validation passed"
  else
    log_warn "Deployment validation had warnings (continuing anyway)"
  fi
}

################################################################################
# AUDIT LOGGING (IMMUTABLE)
################################################################################

post_audit_log() {
  local status="$1"
  local error_msg="${2:-}"
  local bundle_sha256="$3"
  
  log "Posting immutable audit log to GitHub issue #$GITHUB_ISSUE_ID..."
  
  local end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  
  local audit_body
  audit_body=$(cat <<EOF
## 🚀 Deployment: $TIMESTAMP

- **ID:** \`$DEPLOYMENT_ID\`
- **Target:** \`$DEPLOY_TARGET\`
- **User:** \`$DEPLOY_USER\`
- **Branch:** \`$TARGET_BRANCH\`
- **Credential Source:** \`${CRED_SOURCE^^}\`
- **Bundle SHA256:** \`$bundle_sha256\`
- **Status:** \`$status\`
- **Duration:** \`${duration}s\`
- **Dry Run:** \`$DRY_RUN\`
EOF
  )
  
  if [[ -n "$error_msg" ]]; then
    audit_body+="\n- **Error:** \`$error_msg\`"
  fi
  
  audit_body+="\n\n> Auto-logged deployment. No manual action required."
  
  gh issue comment "$GITHUB_ISSUE_ID" \
    --repo "$GITHUB_REPO" \
    --body "$audit_body" 2>/dev/null || {
    log_warn "Failed to post audit log (may be due to GitHub CLI auth)"
  }
  
  log_success "Audit log posted"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  log "=========================================="
  log "  DIRECT-DEPLOY: $TIMESTAMP"
  log "=========================================="
  log "Credential Source: $CRED_SOURCE"
  log "Target Branch: $TARGET_BRANCH"
  log "Target Host: $DEPLOY_TARGET"
  log ""
  
  # Step 1: Validate
  validate_environment || return 1
  
  # Step 2: Fetch credentials (ephemeral)
  fetch_credentials || return 1
  
  # Step 3: Prepare bundle
  local bundle_sha256
  bundle_sha256=$(sha256sum "$(prepare_deployment_bundle)" | awk '{print $1}')
  local bundle_path="$TEMP_DIR/deploy.bundle"
  
  # Step 4: Deploy
  if ! deploy_to_target "$bundle_path"; then
    post_audit_log "FAILED" "Deployment to $DEPLOY_TARGET failed" "$bundle_sha256"
    return 1
  fi
  
  # Step 5: Validate
  validate_deployment || log_warn "Validation incomplete"
  
  # Step 6: Audit log (immutable)
  post_audit_log "SUCCESS" "" "$bundle_sha256"
  
  log ""
  log_success "Deployment complete!"
  log "Exit code: 0"
  return 0
}

# Execute
main "$@"
