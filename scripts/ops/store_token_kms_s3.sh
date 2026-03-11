#!/usr/bin/env bash
set -euo pipefail
# Encrypt a small token with AWS KMS and upload to S3
# Usage: store_token_kms_s3.sh --kms-key-id alias/your-key --bucket my-bucket --key-prefix verifier --value "secret"

usage(){
  cat <<EOF
Usage: $0 --kms-key-id KMS_KEY --bucket BUCKET --key-prefix PREFIX --value TOKEN

Example:
  $0 --kms-key-id alias/verifier-key --bucket nexusshield-secrets --key-prefix verifier --value "ghp_..."
EOF
  exit 1
}

KMS_KEY=""
BUCKET=""
PREFIX=""
VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kms-key-id) KMS_KEY="$2"; shift 2;;
    --bucket) BUCKET="$2"; shift 2;;
    --key-prefix) PREFIX="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$KMS_KEY" || -z "$BUCKET" || -z "$PREFIX" || -z "$VALUE" ]]; then
  usage
fi

TMP_IN="$(mktemp)"
TMP_ENC="$(mktemp)"
trap 'rm -f "$TMP_IN" "$TMP_ENC"' EXIT
printf "%s" "$VALUE" > "$TMP_IN"

aws kms encrypt --key-id "$KMS_KEY" --plaintext fileb://"$TMP_IN" --query CiphertextBlob --output text | base64 --decode > "$TMP_ENC"
S3_KEY="$PREFIX/token.enc"
aws s3 cp "$TMP_ENC" "s3://$BUCKET/$S3_KEY"

echo "Encrypted token uploaded to s3://$BUCKET/$S3_KEY"
echo "To fetch: aws s3 cp s3://$BUCKET/$S3_KEY /tmp/token.enc && aws kms decrypt --ciphertext-blob fileb:///tmp/token.enc --output text --query Plaintext | base64 --decode > /tmp/token"
exit 0
