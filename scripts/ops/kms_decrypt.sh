#!/usr/bin/env bash
set -euo pipefail

# GCP KMS decrypt helper and GitHub secret setter
# Usage:
# ./scripts/ops/kms_decrypt.sh --project PROJECT --location LOCATION --keyring KEYRING --key KEY --ciphertext-file PATH --repo owner/repo --secret-name SECRET_NAME

usage(){
  cat <<EOF
Usage: $0 --project PROJECT --location LOCATION --keyring KEYRING --key KEY --ciphertext-file FILE --repo owner/repo --secret-name SECRET_NAME
Example: ./scripts/ops/kms_decrypt.sh --project myproj --location global --keyring kr --key kube-secret --ciphertext-file ./ct.bin --repo kushin77/self-hosted-runner --secret-name SLACK_WEBHOOK_URL
EOF
  exit 1
}

if [ "$#" -lt 1 ]; then usage; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --location) LOCATION="$2"; shift 2;;
    --keyring) KEYRING="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --ciphertext-file) CTFILE="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --secret-name) SECRET_NAME="$2"; shift 2;;
    --help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [ -z "${PROJECT:-}" ] || [ -z "${LOCATION:-}" ] || [ -z "${KEYRING:-}" ] || [ -z "${KEY:-}" ] || [ -z "${CTFILE:-}" ] || [ -z "${REPO:-}" ] || [ -z "${SECRET_NAME:-}" ]; then
  usage
fi

if [ ! -f "$CTFILE" ]; then
  echo "Ciphertext file not found: $CTFILE" >&2
  exit 2
fi

tmpout=$(mktemp)
trap 'rm -f "$tmpout"' EXIT

# Use gcloud kms decrypt
gcloud kms decrypt --project="$PROJECT" --location="$LOCATION" --keyring="$KEYRING" --key="$KEY" --ciphertext-file="$CTFILE" --plaintext-file="$tmpout"

# Write to GitHub secret
gh secret set "$SECRET_NAME" --repo "$REPO" --body-file "$tmpout"

echo "Decrypted $CTFILE and set secret $SECRET_NAME in $REPO"

exit 0
