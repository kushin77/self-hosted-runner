#!/usr/bin/env bash
set -euo pipefail

# Upload JSONL forensic logs to S3 with optional object lock for immutability.
# Credentials should be provided via short-lived tokens fetched from GSM/Vault/KMS.

BUCKET="${S3_BUCKET:-my-forensic-bucket}"
PREFIX="${S3_PREFIX:-chaos-logs}"
LOG_DIR="${LOG_DIR:-/opt/runner/repo/reports/chaos}"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "AWS credentials are not set. Ensure credentials are fetched via GSM/Vault/KMS at runtime."
  exit 1
fi

echo "Uploading JSONL logs from $LOG_DIR to s3://$BUCKET/$PREFIX/"
for f in "$LOG_DIR"/*.jsonl "$LOG_DIR"/*.txt; do
  [ -e "$f" ] || continue
  key="$PREFIX/$(basename "$f")"
  aws s3 cp "$f" "s3://$BUCKET/$key" --acl bucket-owner-full-control
  echo "Uploaded $f -> s3://$BUCKET/$key"
done

echo "Upload complete. If immutability required, configure bucket-level Object Lock and use a retention mode or legal-hold as appropriate."

exit 0
