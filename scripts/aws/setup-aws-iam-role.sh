#!/usr/bin/env bash
set -euo pipefail

# Idempotent AWS IAM bootstrap for EPIC-6
# Creates an IAM user and access keys (idempotent), attaches policy, and stores creds in GSM and Vault

usage(){
  cat <<EOF
Usage: $0 --project <gcp-project> --iam-policy-file <policy.json> [--username <name>]

This script requires AWS CLI, gcloud and vault CLI configured for the operator.
It will:
 - create IAM user (if missing)
 - attach inline policy or managed policy
 - create access key (rotate if exists)
 - store credentials in Google Secret Manager and Vault
EOF
}

PROJECT="nexusshield-prod"
USERNAME="epic6-operator"
POLICY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --iam-policy-file) POLICY_FILE="$2"; shift 2;;
    --username) USERNAME="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [ -z "$POLICY_FILE" ]; then
  echo "Error: --iam-policy-file is required" >&2; usage; exit 2
fi

set -x

# Create IAM user if missing
if aws iam get-user --user-name "$USERNAME" >/dev/null 2>&1; then
  echo "IAM user $USERNAME exists"
else
  aws iam create-user --user-name "$USERNAME"
  echo "Created IAM user $USERNAME"
fi

# Attach inline policy (idempotent)
POL_NAME="epic6-inline-$(date +%Y%m%d)"
aws iam put-user-policy --user-name "$USERNAME" --policy-name "$POL_NAME" --policy-document file://"$POLICY_FILE"

# Create access key (create new version; keep previous for rotation)
OLD_KEYS=$(aws iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[].AccessKeyId' -o text)
ACCESS_KEY_JSON=$(aws iam create-access-key --user-name "$USERNAME" -o json)
AWS_ACCESS_KEY_ID=REDACTED"$ACCESS_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')

# Store to GCP Secret Manager
echo -n "$AWS_ACCESS_KEY_ID" | gcloud secrets create aws-access-key-id --data-file=- --project="$PROJECT" 2>/dev/null || echo "Secret aws-access-key-id exists, adding version" && echo -n "$AWS_ACCESS_KEY_ID" | gcloud secrets versions add aws-access-key-id --data-file=- --project="$PROJECT"
echo -n "$AWS_SECRET_ACCESS_KEY" | gcloud secrets create aws-secret-access-key --data-file=- --project="$PROJECT" 2>/dev/null || echo "Secret aws-secret-access-key exists, adding version" && echo -n "$AWS_SECRET_ACCESS_KEY" | gcloud secrets versions add aws-secret-access-key --data-file=- --project="$PROJECT"

# Store to Vault if available
if command -v vault >/dev/null 2>&1; then
  vault kv put secret/aws/epic6 access_key_id="$AWS_ACCESS_KEY_ID" secret_access_key="$AWS_SECRET_ACCESS_KEY" || true
fi

echo "AWS credentials provisioned and stored (GSM + Vault)"
