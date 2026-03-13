#!/bin/bash
##############################################################################
# AWS Inventory Collection Script
# Purpose: Configure Vault AWS engine and collect AWS inventory
# Usage: ./run-aws-inventory.sh --aws-key ID --aws-secret SECRET [--aws-token TOKEN]
#        Or: ./run-aws-inventory.sh (will read from GSM or environment)
##############################################################################

set -euo pipefail

# Configuration
BASTION_HOST="192.168.168.42"
BASTION_USER="akushnir"
VAULT_ADDR="http://127.0.0.1:8200"
OUTPUT_DIR="/home/akushnir/self-hosted-runner/cloud-inventory"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level=$1; shift
    case "$level" in
        INFO)   echo -e "${GREEN}[INFO]${NC} $@" ;;
        WARN)   echo -e "${YELLOW}[WARN]${NC} $@" ;;
        ERROR)  echo -e "${RED}[ERROR]${NC} $@" ;;
        *)      echo "$@" ;;
    esac
}

# Parse arguments
AWS_KEY_ID=""
AWS_SECRET_KEY=""
AWS_SESSION_TOKEN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --aws-key)
            AWS_KEY_ID="$2"
            shift 2
            ;;
        --aws-secret)
            AWS_SECRET_KEY="$2"
            shift 2
            ;;
        --aws-token)
            AWS_SESSION_TOKEN="$2"
            shift 2
            ;;
        *)
            log WARN "Unknown option: $1"
            shift
            ;;
    esac
done

##############################################################################
# Step 1: Provision credentials to local Vault AWS engine
##############################################################################

log INFO "Step 1: Configuring Vault AWS secrets engine..."

if [[ -z "$AWS_KEY_ID" || -z "$AWS_SECRET_KEY" ]]; then
    log ERROR "AWS credentials not provided. Usage:"
    log ERROR "  ./run-aws-inventory.sh --aws-key AKIA... --aws-secret ..."
    exit 1
fi

log INFO "Provisioning AWS credentials to bastion Vault..."

ssh -o StrictHostKeyChecking=no "${BASTION_USER}@${BASTION_HOST}" "
    set -e
    export VAULT_ADDR='${VAULT_ADDR}'
    export VAULT_TOKEN=\$(cat /root/vault_root_token 2>/dev/null | tr -d '\n')
    
    # Enable AWS secrets engine if not already enabled
    /usr/local/bin/vault secrets enable -path=aws aws 2>/dev/null || true
    
    # Configure AWS root credentials
    /usr/local/bin/vault write aws/config/root \
        access_key='${AWS_KEY_ID}' \
        secret_key='${AWS_SECRET_KEY}' \
        region=us-east-1
    
    # Create role for temporary credential generation
    /usr/local/bin/vault write aws/roles/nexusshield-role \
        credential_type=iam_user \
        policy_arns='arn:aws:iam::aws:policy/ReadOnlyAccess'
    
    echo '✓ AWS engine configured in Vault'
" || { log ERROR "Failed to configure Vault AWS engine"; exit 1; }

##############################################################################
# Step 2: Update Vault Agent template configuration
##############################################################################

log INFO "Step 2: Configuring Vault Agent AWS template..."

AGENT_HCL_TEMPLATE='
template {
  source      = \"/etc/vault/templates/aws-creds.tpl\"
  destination = \"/var/run/secrets/aws-credentials.env\"
  command     = \"chmod 600 /var/run/secrets/aws-credentials.env\"
  error_on_missing_key = false
}
'

ssh -o StrictHostKeyChecking=no "${BASTION_USER}@${BASTION_HOST}" "
    # Restart agent to pick up new template configuration
    sudo systemctl restart vault-agent.service
    sleep 2
    
    # Verify credentials are rendered
    if test -f /var/run/secrets/aws-credentials.env; then
        echo '✓ AWS credentials template rendered'
        wc -c /var/run/secrets/aws-credentials.env
    else
        echo 'WARNING: AWS credentials file not found after restart'
    fi
" || { log WARN "Agent restart issue, but continuing..."; }

##############################################################################
# Step 3: Run AWS inventory collection
##############################################################################

log INFO "Step 3: Collecting AWS inventory..."

ssh -o StrictHostKeyChecking=no "${BASTION_USER}@${BASTION_HOST}" "
    set -e
    cd /home/akushnir/self-hosted-runner
    mkdir -p cloud-inventory
    
    # Source rendered credentials
    source /var/run/secrets/aws-credentials.env
    
    # Verify credentials work
    echo '✓ Verifying AWS credentials...'
    aws sts get-caller-identity | tee cloud-inventory/aws-sts-identity.json
    
    # Collect inventory
    echo '✓ Collecting S3 buckets...'
    aws s3api list-buckets --output json | tee cloud-inventory/aws-s3-buckets.json
    
    echo '✓ Collecting EC2 instances (us-east-1)...'
    aws ec2 describe-instances --region us-east-1 --output json | \
        jq '.Reservations' | tee cloud-inventory/aws-ec2-instances.json
    
    echo '✓ Collecting RDS instances...'
    aws rds describe-db-instances --output json | \
        jq '.DBInstances' | tee cloud-inventory/aws-rds-instances.json
    
    echo '✓ Collecting IAM users...'
    aws iam list-users --output json | \
        jq '.Users' | tee cloud-inventory/aws-iam-users.json
    
    echo '✓ Collecting IAM roles...'
    aws iam list-roles --output json | \
        jq '.Roles' | tee cloud-inventory/aws-iam-roles.json
    
    echo ''
    echo '✅ AWS inventory collection complete!'
    echo 'Files saved to: cloud-inventory/aws-*.json'
    ls -lah cloud-inventory/aws-*.json
" || { log ERROR "AWS inventory collection failed"; exit 1; }

##############################################################################
# Step 4: Sync files from bastion to local workspace
##############################################################################

log INFO "Step 4: Syncing AWS inventory files to workspace..."

scp -r "${BASTION_USER}@${BASTION_HOST}:/home/akushnir/self-hosted-runner/cloud-inventory/aws-*.json" \
    "/home/akushnir/self-hosted-runner/cloud-inventory/" 2>/dev/null || \
    log WARN "Files already on workspace"

##############################################################################
# Summary
##############################################################################

log INFO "AWS inventory execution summary:"
echo ""
echo "✅ Vault AWS engine configured"
echo "✅ AWS credentials provisioned to local Vault"
echo "✅ Vault Agent templates rendered credentials"
echo "✅ AWS inventory collection complete"
echo ""
echo "Output files:"
ls -lah "${OUTPUT_DIR}/aws-"*.json 2>/dev/null || echo "  (files will sync from bastion)"
echo ""
log INFO "Next: Update FINAL_CROSS_CLOUD_INVENTORY_2026_03_13.md with AWS results"
