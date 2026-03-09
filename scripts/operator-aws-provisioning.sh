#!/bin/bash
################################################################################
# AWS Secrets Manager & KMS Provisioning - OPERATOR EXECUTION
# Description: Provisions AWS Secrets Manager secrets and KMS key for credentials
# Usage: 
#   1. Configure AWS credentials: aws configure
#   2. ./scripts/operator-aws-provisioning.sh [--dry-run] [--verbose]
# Requires: aws CLI v2, jq, valid AWS credentials with SecretsManager + KMS permissions
################################################################################

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
KMS_KEY_DESC="runner-credential-encryption-key"
SECRET_PREFIX="runner"
TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"

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

# Verify AWS credentials and region
verify_aws_credentials() {
    log INFO "Verifying AWS credentials and permissions..."
    
    # Check AWS CLI installed
    if ! command -v aws &>/dev/null; then
        log ERROR "AWS CLI v2 not found. Install from: https://aws.amazon.com/cli/"
        return 1
    fi
    
    # Verify credentials are configured
    if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
        log ERROR "AWS credentials not configured or invalid"
        log INFO "Run: aws configure"
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
    local user_arn=$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")
    
    log SUCCESS "AWS credentials verified"
    log INFO "  Account: $account_id"
    log INFO "  User: $user_arn"
    log INFO "  Region: $AWS_REGION"
}

# Create KMS key for encryption
create_kms_key() {
    log INFO "Creating KMS key for credentials encryption..."
    
    # Check if key already exists
    local existing_key=$(aws kms list-keys --region "$AWS_REGION" --query "Keys[].KeyArn" --output text 2>/dev/null | grep -F "$KMS_KEY_DESC" || echo "")
    
    if [[ -n "$existing_key" ]]; then
        log WARN "KMS key already exists: $existing_key"
        echo "$existing_key" | awk -F'/' '{print $NF}'
        return 0
    fi
    
    log INFO "Creating new KMS key..."
    
    local cmd="aws kms create-key"
    cmd="$cmd --description '$KMS_KEY_DESC'"
    cmd="$cmd --key-usage ENCRYPT_DECRYPT"
    cmd="$cmd --origin AWS_KMS"
    cmd="$cmd --region '$AWS_REGION'"
    cmd="$cmd --query 'KeyMetadata.KeyId'"
    cmd="$cmd --output text"
    
    local key_id=$(run_cmd "$cmd" 2>&1 | grep -v 'DRY-RUN' | tail -1)
    
    if [[ -z "$key_id" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log ERROR "Failed to create KMS key"
        return 1
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log SUCCESS "KMS key created: $key_id"
        
        # Create alias
        local alias="alias/runner-credentials"
        aws kms create-alias --alias-name "$alias" --target-key-id "$key_id" --region "$AWS_REGION" 2>/dev/null || \
            log WARN "Alias $alias already exists or could not be created"
        
        echo "$key_id"
    fi
}

# Create SSH credentials secret
provision_ssh_credentials() {
    log INFO "Provisioning SSH credentials secret..."
    
    # If running on bastion, use existing key; otherwise generate
    local ssh_key
    if [[ -f "/home/${TARGET_USER}/.ssh/id_rsa" ]]; then
        log INFO "Using existing SSH key from target host"
        ssh_key=$(cat "/home/${TARGET_USER}/.ssh/id_rsa")
    else
        log WARN "SSH key not found at /home/${TARGET_USER}/.ssh/id_rsa"
        log INFO "Skipping SSH credentials - use existing key or generate locally"
        return 0
    fi
    
    local secret_name="${SECRET_PREFIX}/ssh-credentials"
    
    # Check if secret already exists
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        log WARN "Secret already exists: $secret_name"
        log INFO "Updating secret with current credentials..."
        
        run_cmd "aws secretsmanager update-secret"
        run_cmd "  --secret-id '$secret_name'"
        run_cmd "  --secret-string '{\"ssh_key\":\"'$(echo $ssh_key | sed 's/"/\\"/g')'\"}'"
        run_cmd "  --region '$AWS_REGION'"
    else
        log INFO "Creating new secret: $secret_name"
        
        run_cmd "aws secretsmanager create-secret"
        run_cmd "  --name '$secret_name'"
        run_cmd "  --description 'SSH private key for runner deployment'"
        run_cmd "  --secret-string '{\"ssh_key\":\"'$(echo $ssh_key | sed 's/"/\\"/g')'\"}'"
        run_cmd "  --region '$AWS_REGION'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log SUCCESS "SSH credentials secret created: $secret_name"
        fi
    fi
}

# Create AWS credentials secret
provision_aws_credentials() {
    log INFO "Provisioning AWS credentials secret..."
    
    local secret_name="${SECRET_PREFIX}/aws-credentials"
    
    # Check if secret already exists
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        log WARN "Secret already exists: $secret_name"
    else
        log INFO "Creating new secret: $secret_name"
        
        # Get current temporary credentials (if STS is being used)
        run_cmd "aws secretsmanager create-secret"
        run_cmd "  --name '$secret_name'"
        run_cmd "  --description 'AWS credentials for runner deployment'"
        run_cmd "  --secret-string '{\"access_key_id\":\"AKIAIOSFODNN7EXAMPLE\",\"secret_access_key\":\"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\"}'"
        run_cmd "  --region '$AWS_REGION'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log WARN "AWS credentials secret created with placeholder values"
            log INFO "Update with real credentials: aws secretsmanager update-secret --secret-id $secret_name --secret-string '...'"
        fi
    fi
}

# Create DockerHub credentials secret
provision_dockerhub_credentials() {
    log INFO "Provisioning DockerHub credentials secret..."
    
    local secret_name="${SECRET_PREFIX}/dockerhub-credentials"
    
    # Check if secret already exists
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        log WARN "Secret already exists: $secret_name"
    else
        log INFO "Creating new secret: $secret_name"
        
        run_cmd "aws secretsmanager create-secret"
        run_cmd "  --name '$secret_name'"
        run_cmd "  --description 'DockerHub credentials for runner container pulls'"
        run_cmd "  --secret-string '{\"username\":\"YOUR_DOCKERHUB_USERNAME\",\"password\":\"YOUR_DOCKERHUB_PAT\"}'"
        run_cmd "  --region '$AWS_REGION'"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log WARN "DockerHub credentials secret created with placeholder values"
            log INFO "Update with real credentials: aws secretsmanager update-secret --secret-id $secret_name --secret-string '...'"
        fi
    fi
}

# Grant IAM permissions for runner role
grant_runner_iam_permissions() {
    log INFO "Creating IAM policy for runner service..."
    
    local policy_name="runner-secrets-access-policy"
    local policy_doc='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadSecretsManager",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "arn:aws:secretsmanager:'"$AWS_REGION"':*:secret:'"$SECRET_PREFIX"'/*"
        },
        {
            "Sid": "DecryptWithKMS",
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey"
            ],
            "Resource": "arn:aws:kms:'"$AWS_REGION"':*:key/*"
        },
        {
            "Sid": "ListSecrets",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:ListSecrets"
            ],
            "Resource": "*"
        }
    ]
}'
    
    # Check if policy exists
    if aws iam get-role-policy --role-name "runner-role" --policy-name "$policy_name" >/dev/null 2>&1; then
        log WARN "IAM policy already exists: $policy_name"
    else
        log INFO "Creating inline policy for runner role..."
        
        if [[ "$DRY_RUN" != "true" ]]; then
            if aws iam get-role --role-name "runner-role" >/dev/null 2>&1; then
                aws iam put-role-policy \
                    --role-name "runner-role" \
                    --policy-name "$policy_name" \
                    --policy-document "$policy_doc"
                
                log SUCCESS "IAM policy attached to runner role"
            else
                log WARN "Runner role does not exist - create with: aws iam create-role --role-name runner-role ..."
            fi
        fi
    fi
}

# Verify secrets accessibility
verify_secrets() {
    log INFO "Verifying secrets accessibility..."
    
    local secrets=(
        "${SECRET_PREFIX}/ssh-credentials"
        "${SECRET_PREFIX}/aws-credentials"
        "${SECRET_PREFIX}/dockerhub-credentials"
    )
    
    for secret in "${secrets[@]}"; do
        if aws secretsmanager describe-secret --secret-id "$secret" --region "$AWS_REGION" >/dev/null 2>&1; then
            log SUCCESS "✓ Secret accessible: $secret"
        else
            log WARN "✗ Secret not accessible: $secret"
        fi
    done
}

# Main execution
main() {
    log INFO "========================================="
    log INFO "AWS Secrets Manager Provisioning"
    log INFO "========================================="
    log INFO "AWS Region: $AWS_REGION"
    log INFO "Target: ${TARGET_USER}@${TARGET_HOST}:22"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "DRY-RUN MODE: No changes will be made"
    fi
    
    # Execute provisioning steps
    verify_aws_credentials || exit 1
    create_kms_key || exit 1
    provision_ssh_credentials || exit 1
    provision_aws_credentials || exit 1
    provision_dockerhub_credentials || exit 1
    grant_runner_iam_permissions || exit 1
    verify_secrets || exit 1
    
    log SUCCESS "========================================="
    log SUCCESS "AWS Provisioning Complete!"
    log SUCCESS "========================================="
    log SUCCESS "Secrets ready for credential distribution"
    log INFO "Next: Deploy Oracle-local GSM provisioning (Phase 3)"
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
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose] [--region REGION]"
            exit 1
            ;;
    esac
done

main
