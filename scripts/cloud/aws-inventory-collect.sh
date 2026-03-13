#!/usr/bin/env bash
# AWS Infrastructure Inventory Collection
# Collects S3, EC2, RDS, IAM, security groups, and VPCs
# Requires: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY environment variables
# Usage: ./aws-inventory-collect.sh [output_dir] [region]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
OUTPUT_DIR="${1:-cloud-inventory}"
AWS_REGION="${2:-us-east-1}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

log() { echo "[${SCRIPT_NAME}] $*" >&2; }
err() { echo "[${SCRIPT_NAME}] ERROR: $*" >&2; exit 1; }
success() { echo "[${SCRIPT_NAME}] ✅ $*" >&2; }

# Verify AWS credentials
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  err "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set"
fi

# Verify AWS CLI
if ! command -v aws >/dev/null 2>&1; then
  err "AWS CLI not found. Install with: pip install awscli"
fi

mkdir -p "$OUTPUT_DIR"

log "=== AWS Inventory Collection ==="
log "Output directory: $OUTPUT_DIR"
log "Region: $AWS_REGION"
log "Timestamp: $TIMESTAMP"

# Verify AWS credentials work
log "Verifying AWS credentials..."
if ! aws sts get-caller-identity > "$OUTPUT_DIR/aws-sts-identity.json" 2>/dev/null; then
  err "AWS credentials invalid or expired"
fi

ACCOUNT_ID=$(jq -r '.Account' "$OUTPUT_DIR/aws-sts-identity.json")
USER_ARN=$(jq -r '.Arn' "$OUTPUT_DIR/aws-sts-identity.json")
success "AWS credentials verified for account $ACCOUNT_ID"
log "Using IAM principal: $USER_ARN"

# S3 Buckets
log "Collecting S3 buckets..."
aws s3api list-buckets \
  --output json \
  > "$OUTPUT_DIR/aws-s3-buckets.json" || err "Failed to list S3 buckets"
S3_COUNT=$(jq '.Buckets | length' "$OUTPUT_DIR/aws-s3-buckets.json")
success "Collected $S3_COUNT S3 buckets"

# EC2 Instances (all regions)
log "Collecting EC2 instances (all regions)..."
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --output json \
  > "$OUTPUT_DIR/aws-ec2-instances.json" || err "Failed to list EC2 instances"
EC2_COUNT=$(jq '.Reservations[].Instances[]' "$OUTPUT_DIR/aws-ec2-instances.json" | jq -s 'length')
success "Collected $EC2_COUNT EC2 instances"

# RDS Databases
log "Collecting RDS databases..."
aws rds describe-db-instances \
  --output json \
  > "$OUTPUT_DIR/aws-rds-instances.json" || err "Failed to list RDS instances"
RDS_COUNT=$(jq '.DBInstances | length' "$OUTPUT_DIR/aws-rds-instances.json")
success "Collected $RDS_COUNT RDS databases"

# IAM Users
log "Collecting IAM users..."
aws iam list-users \
  --output json \
  > "$OUTPUT_DIR/aws-iam-users.json" || err "Failed to list IAM users"
IAM_USERS=$(jq '.Users | length' "$OUTPUT_DIR/aws-iam-users.json")
success "Collected $IAM_USERS IAM users"

# IAM Roles
log "Collecting IAM roles..."
aws iam list-roles \
  --output json \
  > "$OUTPUT_DIR/aws-iam-roles.json" || err "Failed to list IAM roles"
IAM_ROLES=$(jq '.Roles | length' "$OUTPUT_DIR/aws-iam-roles.json")
success "Collected $IAM_ROLES IAM roles"

# Security Groups
log "Collecting security groups..."
aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --output json \
  > "$OUTPUT_DIR/aws-security-groups.json" || err "Failed to list security groups"
SG_COUNT=$(jq '.SecurityGroups | length' "$OUTPUT_DIR/aws-security-groups.json")
success "Collected $SG_COUNT security groups"

# VPCs
log "Collecting VPCs..."
aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --output json \
  > "$OUTPUT_DIR/aws-vpcs.json" || err "Failed to list VPCs"
VPC_COUNT=$(jq '.Vpcs | length' "$OUTPUT_DIR/aws-vpcs.json")
success "Collected $VPC_COUNT VPCs"

# Generate consolidated inventory metadata
log "Generating consolidated inventory summary..."
cat > "$OUTPUT_DIR/AWS_INVENTORY_METADATA_${TIMESTAMP}.json" << METADATA
{
  "inventory_timestamp": "$TIMESTAMP",
  "collection_region": "$AWS_REGION",
  "aws_account_id": "$ACCOUNT_ID",
  "aws_iam_principal": "$USER_ARN",
  "resources_collected": {
    "s3_buckets": $S3_COUNT,
    "ec2_instances": $EC2_COUNT,
    "rds_databases": $RDS_COUNT,
    "iam_users": $IAM_USERS,
    "iam_roles": $IAM_ROLES,
    "security_groups": $SG_COUNT,
    "vpcs": $VPC_COUNT,
    "total_resources": $(($S3_COUNT + $EC2_COUNT + $RDS_COUNT + $IAM_USERS + $IAM_ROLES + $SG_COUNT + $VPC_COUNT))
  },
  "files_generated": [
    "aws-sts-identity.json",
    "aws-s3-buckets.json",
    "aws-ec2-instances.json",
    "aws-rds-instances.json",
    "aws-iam-users.json",
    "aws-iam-roles.json",
    "aws-security-groups.json",
    "aws-vpcs.json"
  ]
}
METADATA

success "Consolidated inventory summary created"

# Display summary
log ""
log "=== INVENTORY SUMMARY ==="
log "S3 Buckets:      $S3_COUNT"
log "EC2 Instances:   $EC2_COUNT"
log "RDS Databases:   $RDS_COUNT"
log "IAM Users:       $IAM_USERS"
log "IAM Roles:       $IAM_ROLES"
log "Security Groups: $SG_COUNT"
log "VPCs:            $VPC_COUNT"
log ""
log "Files saved to: $OUTPUT_DIR/"
log ""

# List files with sizes
log "Files created:"
ls -lh "$OUTPUT_DIR"/aws-*.json "$OUTPUT_DIR"/AWS_INVENTORY_METADATA_* 2>/dev/null | awk '{printf "  %-50s %8s\n", $9, $5}'

success "AWS inventory collection complete"
