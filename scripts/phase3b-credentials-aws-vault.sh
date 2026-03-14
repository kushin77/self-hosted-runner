#!/usr/bin/env bash
set -euo pipefail

# Phase 3b: AWS Vault Credentials Configuration
# Purpose: Configure AWS IAM credentials for Vault integration
# Part of the nexusshield-prod deployment automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [PHASE3B-CREDS] $*" >&2
}

log_success() {
  echo "✅ $*" >&2
}

log_error() {
  echo "❌ $*" >&2
  return 1
}

# Check prerequisites
check_prerequisites() {
  log "Checking prerequisites for AWS Vault credential setup..."
  
  # Check AWS CLI
  if ! command -v aws &>/dev/null; then
    log_error "aws-cli not found"
    return 1
  fi
  
  # Check gcloud
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud not found"
    return 1
  fi
  
  # Check for required GCP project
  local project_id
  project_id="$(gcloud config get-value project 2>/dev/null)" || true
  if [ -z "$project_id" ]; then
    log_error "GCP project not configured"
    return 1
  fi
  
  log_success "Prerequisites check passed"
}

# Configure AWS credentials via vault
configure_aws_vault() {
  log "Configuring AWS Vault credentials..."
  
  # Read AWS credentials from environment or GSM
  local aws_access_key_id="${AWS_ACCESS_KEY_ID:-}"
  local aws_secret_access_key="${AWS_SECRET_ACCESS_KEY:-}"
  
  # If not in environment, try to read from GSM
  if [ -z "$aws_access_key_id" ] || [ -z "$aws_secret_access_key" ]; then
    log "Reading AWS credentials from Google Secret Manager..."
    
    aws_access_key_id="$(gcloud secrets versions access latest --secret=aws-access-key-id --project="${GCP_PROJECT_ID:-$(gcloud config get-value project)}" 2>/dev/null)" || {
      log_error "Failed to read aws-access-key-id from GSM"
      return 1
    }
    
    aws_secret_access_key="$(gcloud secrets versions access latest --secret=aws-secret-access-key --project="${GCP_PROJECT_ID:-$(gcloud config get-value project)}" 2>/dev/null)" || {
      log_error "Failed to read aws-secret-access-key from GSM"
      return 1
    }
  fi
  
  # Configure AWS CLI credentials securely
  local aws_config_dir="${HOME}/.aws"
  mkdir -p "$aws_config_dir"
  chmod 700 "$aws_config_dir"
  
  # Create credentials file with restricted permissions
  local credentials_file="$aws_config_dir/credentials"
  cat > "$credentials_file" << EOF
[default]
aws_access_key_id = $aws_access_key_id
aws_secret_access_key = $aws_secret_access_key
EOF
  
  chmod 600 "$credentials_file"
  
  log_success "AWS credentials configured"
}

# Verify vault access with AWS credentials
verify_vault_access() {
  log "Verifying Vault access with AWS credentials..."
  
  # Set AWS environment for verification
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  
  # Test AWS CLI access
  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "Failed to verify AWS access"
    return 1
  fi
  
  log_success "Vault access verified"
}

# Record deployment status
record_status() {
  local status_file="$REPO_ROOT/logs/phase3b-credentials-aws-vault.status"
  mkdir -p "$(dirname "$status_file")"
  
  cat > "$status_file" << EOF
timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
phase=3b
component=credentials_aws_vault
status=$1
message=$2
EOF
  
  log "Status recorded: $1"
}

# Main execution
main() {
  log "Starting Phase 3b: AWS Vault Credentials Configuration"
  
  if ! check_prerequisites; then
    record_status "FAILED" "Prerequisites check failed"
    return 1
  fi
  
  if ! configure_aws_vault; then
    record_status "FAILED" "AWS Vault configuration failed"
    return 1
  fi
  
  if ! verify_vault_access; then
    record_status "FAILED" "Vault access verification failed"
    return 1
  fi
  
  record_status "SUCCESS" "AWS Vault credentials configured and verified"
  log_success "Phase 3b completed successfully"
  
  return 0
}

# Run main function if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
