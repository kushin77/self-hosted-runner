#!/bin/bash
################################################################################
# Google Secret Manager Provisioning - OPERATOR EXECUTION
# Description: Provisions GCP Secret Manager secrets for credentials
# Usage:
#   1. Authenticate: gcloud auth application-default login
#   2. Set project: gcloud config set project PROJECT_ID
#   3. ./scripts/operator-gcp-provisioning.sh [--dry-run] [--verbose]
# Requires: gcloud CLI, valid GCP credentials, Secret Manager API enabled
################################################################################

set -e

# Configuration
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
GCP_REGION="${GCP_REGION:-us-central1}"
SECRET_PREFIX="runner"
TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"

# Service account for runner
RUNNER_SA_NAME="runner-watcher"
RUNNER_SA_EMAIL="${RUNNER_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

# Flags
DRY_RUN=${DRY_RUN:-false}
VERBOSE=${VERBOSE:-false}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log() {
    local level=$1; shift
    local message="$@"
    local timestamp=$(date '+[%Y-%m-%d %H:%M:%S]')
    
    case "$level" in
        INFO)   echo -e "${BLUE}${timestamp} ℹ️  ${message}${NC}" ;;
        SUCCESS) echo -e "${GREEN}${timestamp} ✅ ${message}${NC}" ;;
        WARN)   echo -e "${YELLOW}${timestamp} ⚠️  ${message}${NC}" ;;
        ERROR)  echo -e "${RED}${timestamp} ❌ ${message}${NC}" ;;
    esac
}

run_cmd() {
    local cmd="$@"
    if [[ "$VERBOSE" == "true" ]]; then
        log INFO "Executing: $cmd"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    eval "$cmd"
}

# Verify GCP credentials and project
verify_gcp_credentials() {
    log INFO "Verifying GCP credentials and project..."
    
    # Check gcloud CLI installed
    if ! command -v gcloud &>/dev/null; then
        log ERROR "gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Get current project
    if [[ -z "$GCP_PROJECT" ]]; then
        log ERROR "GCP project not set. Run: gcloud config set project PROJECT_ID"
        return 1
    fi
    
    # Verify authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
        log ERROR "Not authenticated with gcloud. Run: gcloud auth application-default login"
        return 1
    fi
    
    local account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    
    log SUCCESS "GCP credentials verified"
    log INFO "  Project: $GCP_PROJECT"
    log INFO "  Account: $account"
    log INFO "  Region: $GCP_REGION"
}

# Enable Secret Manager API
enable_secrets_api() {
    log INFO "Enabling Secret Manager API..."
    
    run_cmd "gcloud services enable secretmanager.googleapis.com --project=$GCP_PROJECT" || \
        log WARN "Secret Manager API may already be enabled"
    
    log SUCCESS "Secret Manager API enabled (or already active)"
}

# Create/update SSH credentials secret
provision_ssh_credentials() {
    log INFO "Provisioning SSH credentials secret..."
    
    # If running on bastion, use existing key; otherwise use placeholder
    local ssh_key
    if [[ -f "/home/${TARGET_USER}/.ssh/id_rsa" ]]; then
        log INFO "Using existing SSH key from target host"
        ssh_key=$(cat "/home/${TARGET_USER}/.ssh/id_rsa" | base64 -w0)
    else
        log WARN "SSH key not found - using placeholder"
        ssh_key=$(echo "-----BEGIN RSA PRIVATE KEY-----
PLACEHOLDER=
-----END RSA PRIVATE KEY-----" | base64 -w0)
    fi
    
    local secret_name="${SECRET_PREFIX}-ssh-key"
    
    # Check if secret already exists
    if gcloud secrets describe "$secret_name" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        log INFO "Secret already exists: $secret_name (updating...)"
        
        run_cmd "gcloud secrets versions add '$secret_name' --project='$GCP_PROJECT' --data-file=- <<< '$ssh_key'"
    else
        log INFO "Creating new secret: $secret_name"
        
        run_cmd "gcloud secrets create '$secret_name'"
        run_cmd "  --project='$GCP_PROJECT'"
        run_cmd "  --replication-policy='automatic'"
        run_cmd "  --data-file=- <<< '$ssh_key'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log SUCCESS "SSH credentials secret created: $secret_name"
        fi
    fi
}

# Create/update AWS credentials secret
provision_aws_credentials() {
    log INFO "Provisioning AWS credentials secret..."
    
    local secret_name="${SECRET_PREFIX}-aws-credentials"
    
    # Check if secret already exists
    if gcloud secrets describe "$secret_name" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        log INFO "Secret already exists: $secret_name (update with: gcloud secrets versions add)"
    else
        log INFO "Creating new secret: $secret_name"
        
        local creds='{
  "access_key_id": "REDACTED_AWS_ACCESS_KEY_ID",
  "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "region": "us-east-1"
}'
        
        run_cmd "gcloud secrets create '$secret_name'"
        run_cmd "  --project='$GCP_PROJECT'"
        run_cmd "  --replication-policy='automatic'"
        run_cmd "  --data-file=- <<< '$creds'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log WARN "AWS credentials secret created with placeholder values"
            log INFO "Update: gcloud secrets versions add $secret_name --data-file=credentials.json"
        fi
    fi
}

# Create/update DockerHub credentials secret
provision_dockerhub_credentials() {
    log INFO "Provisioning DockerHub credentials secret..."
    
    local secret_name="${SECRET_PREFIX}-dockerhub-credentials"
    
    # Check if secret already exists
    if gcloud secrets describe "$secret_name" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        log INFO "Secret already exists: $secret_name"
    else
        log INFO "Creating new secret: $secret_name"
        
        local creds='{
  "username": "YOUR_DOCKERHUB_USERNAME",
  "password": "YOUR_DOCKERHUB_PAT"
}'
        
        run_cmd "gcloud secrets create '$secret_name'"
        run_cmd "  --project='$GCP_PROJECT'"
        run_cmd "  --replication-policy='automatic'"
        run_cmd "  --data-file=- <<< '$creds'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log WARN "DockerHub credentials secret created with placeholder values"
        fi
    fi
}

# Create service account for runner
create_runner_service_account() {
    log INFO "Creating runner service account..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "$RUNNER_SA_EMAIL" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        log WARN "Service account already exists: $RUNNER_SA_EMAIL"
    else
        log INFO "Creating service account: $RUNNER_SA_EMAIL"
        
        run_cmd "gcloud iam service-accounts create '$RUNNER_SA_NAME'"
        run_cmd "  --project='$GCP_PROJECT'"
        run_cmd "  --display-name='Runner Credential Watcher Service Account'"
        run_cmd "  --description='Service account for runner credential distribution and management'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log SUCCESS "Service account created: $RUNNER_SA_EMAIL"
        fi
    fi
}

# Grant Secret Manager access to service account
grant_secret_manager_access() {
    log INFO "Granting Secret Manager access to service account..."
    
    local role="roles/secretmanager.secretAccessor"
    
    run_cmd "gcloud projects add-iam-policy-binding '$GCP_PROJECT'"
    run_cmd "  --member='serviceAccount:$RUNNER_SA_EMAIL'"
    run_cmd "  --role='$role'"
    run_cmd "  --condition=None"
    
    log SUCCESS "Secret Manager access granted to service account"
}

# Create and download service account key
create_service_account_key() {
    log INFO "Creating service account key..."
    
    local key_file="/tmp/runner-sa-key.json"
    
    # Check if recent key already exists
    local existing_keys=$(gcloud iam service-accounts keys list \
        --iam-account="$RUNNER_SA_EMAIL" \
        --project="$GCP_PROJECT" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ $existing_keys -gt 2 ]]; then
        log WARN "Multiple service account keys exist - consider rotating old ones"
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        run_cmd "gcloud iam service-accounts keys create '$key_file'"
        run_cmd "  --iam-account='$RUNNER_SA_EMAIL'"
        run_cmd "  --project='$GCP_PROJECT'"
        
        if [[ -f "$key_file" ]]; then
            log SUCCESS "Service account key created: $key_file"
            log INFO "Store this securely in: /var/run/secrets/gcp-sa.json"
            # Show key location
            ls -lh "$key_file" | awk '{print "  Size: " $5 " | Permissions: " $1 " | Path: " $NF}'
        fi
    fi
}

# Verify secrets accessibility
verify_secrets() {
    log INFO "Verifying secrets accessibility..."
    
    local secrets=(
        "${SECRET_PREFIX}-ssh-key"
        "${SECRET_PREFIX}-aws-credentials"
        "${SECRET_PREFIX}-dockerhub-credentials"
    )
    
    for secret in "${secrets[@]}"; do
        if gcloud secrets describe "$secret" --project="$GCP_PROJECT" >/dev/null 2>&1; then
            log SUCCESS "✓ Secret accessible: $secret"
        else
            log WARN "✗ Secret not found: $secret"
        fi
    done
}

# Main execution
main() {
    log INFO "========================================="
    log INFO "Google Secret Manager Provisioning"
    log INFO "========================================="
    log INFO "GCP Project: $GCP_PROJECT"
    log INFO "GCP Region: $GCP_REGION"
    log INFO "Target: ${TARGET_USER}@${TARGET_HOST}:22"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "DRY-RUN MODE: No changes will be made"
    fi
    
    # Execute provisioning steps
    verify_gcp_credentials || exit 1
    enable_secrets_api || exit 1
    provision_ssh_credentials || exit 1
    provision_aws_credentials || exit 1
    provision_dockerhub_credentials || exit 1
    create_runner_service_account || exit 1
    grant_secret_manager_access || exit 1
    create_service_account_key || exit 1
    verify_secrets || exit 1
    
    log SUCCESS "========================================="
    log SUCCESS "GCP Provisioning Complete!"
    log SUCCESS "========================================="
    log SUCCESS "Secrets and service account ready"
    log INFO "Next: Deploy watcher service to receive credentials"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --project)
            GCP_PROJECT="$2"
            shift 2
            ;;
        --region)
            GCP_REGION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose] [--project PROJECT_ID] [--region REGION]"
            exit 1
            ;;
    esac
done

main
