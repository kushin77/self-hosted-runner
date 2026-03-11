#!/usr/bin/env bash
set -euo pipefail
# Encrypt an SSH key with AWS KMS and upload to S3 (idempotent-ish)
# Usage: store_ssh_kms_s3.sh --kms-key-id alias/your-key --bucket my-bucket --key-prefix verifier --file /tmp/verifier_key

usage(){
  cat <<EOF
Usage: $0 --kms-key-id KMS_KEY --bucket BUCKET --key-prefix PREFIX --file /path/to/key

Example:
  $0 --kms-key-id alias/verifier-key --bucket nexusshield-secrets --key-prefix verifier --file /tmp/verifier_key
EOF
  exit 1
}

KMS_KEY=""
BUCKET=""
PREFIX=""
KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kms-key-id) KMS_KEY="$2"; shift 2;;
    --bucket) BUCKET="$2"; shift 2;;
    --key-prefix) PREFIX="$2"; shift 2;;
    --file) KEY_FILE="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$KMS_KEY" || -z "$BUCKET" || -z "$PREFIX" || -z "$KEY_FILE" ]]; then
  usage
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Key file not found: $KEY_FILE" >&2
  exit 2
fi

TMP_ENC="$(mktemp)"
trap 'rm -f "$TMP_ENC"' EXIT

aws kms encrypt --key-id "$KMS_KEY" --plaintext fileb://"$KEY_FILE" --query CiphertextBlob --output text | base64 --decode > "$TMP_ENC"
S3_KEY="$PREFIX/$(basename "$KEY_FILE").enc"
aws s3 cp "$TMP_ENC" "s3://$BUCKET/$S3_KEY"

echo "Encrypted key uploaded to s3://$BUCKET/$S3_KEY"
echo "To fetch: aws s3 cp s3://$BUCKET/$S3_KEY /tmp/enc && aws kms decrypt --ciphertext-blob fileb:///tmp/enc --output text --query Plaintext | base64 --decode > /tmp/verifier_key"
exit 0
