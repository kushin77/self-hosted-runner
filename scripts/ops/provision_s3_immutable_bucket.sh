#!/usr/bin/env bash
set -euo pipefail

# Create S3 bucket with Object Lock for immutable forensic log storage
# Idempotent: safe to re-run; bucket creation skipped if exists
# Credentials fetched at runtime via GSM/Vault/KMS — never hardcoded

BUCKET="${S3_BUCKET:-chaos-forensic-logs}"
REGION="${AWS_REGION:-us-east-1}"
RETENTION_DAYS="${RETENTION_DAYS:-90}"
RETENTION_MODE="${RETENTION_MODE:-GOVERNANCE}"

echo "=== S3 Immutable Bucket Provisioner ==="
echo "Bucket:    $BUCKET"
echo "Region:    $REGION"
echo "Retention: $RETENTION_DAYS days ($RETENTION_MODE)"

# Fetch credentials if not already set
if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  # shellcheck source=fetch_credentials.sh
  source "$SCRIPT_DIR/fetch_credentials.sh" || {
    echo "ERROR: Could not fetch credentials. Set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or configure GSM/Vault/KMS."
    exit 1
  }
fi

# Check if bucket already exists (idempotent)
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket s3://$BUCKET already exists — skipping creation."
else
  echo "Creating bucket s3://$BUCKET with Object Lock enabled..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --object-lock-enabled-for-bucket
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" \
      --object-lock-enabled-for-bucket
  fi
  echo "Bucket created."
fi

# Enable versioning (required for Object Lock)
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# Configure default Object Lock retention
echo "Setting default retention: $RETENTION_DAYS days in $RETENTION_MODE mode..."
aws s3api put-object-lock-configuration \
  --bucket "$BUCKET" \
  --object-lock-configuration "{
    \"ObjectLockEnabled\": \"Enabled\",
    \"Rule\": {
      \"DefaultRetention\": {
        \"Mode\": \"$RETENTION_MODE\",
        \"Days\": $RETENTION_DAYS
      }
    }
  }"

# Block all public access
echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable server-side encryption (AES-256)
echo "Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Apply lifecycle policy — transition to Glacier after 30 days
echo "Applying lifecycle policy (Glacier after 30 days)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "archive-to-glacier",
      "Status": "Enabled",
      "Filter": {"Prefix": "chaos-logs/"},
      "Transitions": [{"Days": 30, "StorageClass": "GLACIER"}]
    }]
  }'

echo ""
echo "=== Bucket Provisioned Successfully ==="
echo "  Bucket:      s3://$BUCKET"
echo "  Region:      $REGION"
echo "  Object Lock: Enabled ($RETENTION_MODE, $RETENTION_DAYS days)"
echo "  Encryption:  AES-256"
echo "  Versioning:  Enabled"
echo "  Lifecycle:   Glacier after 30 days"
echo "  Public:      Blocked"
echo ""
echo "Upload logs with:"
echo "  S3_BUCKET=$BUCKET scripts/ops/upload_jsonl_to_s3.sh"

# Audit: append provisioning event
AUDIT_LOG="${AUDIT_LOG:-/tmp/s3-provision-audit.jsonl}"
echo "{\"event\":\"s3_bucket_provisioned\",\"timestamp\":\"$(date -u +%FT%TZ)\",\"bucket\":\"$BUCKET\",\"region\":\"$REGION\",\"retention_days\":$RETENTION_DAYS,\"mode\":\"$RETENTION_MODE\",\"idempotent\":true}" >> "$AUDIT_LOG"
echo "Audit event written to $AUDIT_LOG"
