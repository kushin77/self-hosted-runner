#!/usr/bin/env bash
set -euo pipefail

# Idempotent GCP service account bootstrap for EPIC-6
# Creates service account, assigns roles, creates key, stores key JSON in GSM and Vault

usage(){
  cat <<EOF
Usage: $0 --project <gcp-project> --sa-name <name> --roles "roles/viewer,roles/storage.admin"

This script requires: gcloud, jq, and vault CLI (optional).
It will:
 - create a service account if missing
 - bind IAM roles to the service account
 - create a key JSON and store it in Google Secret Manager and Vault
EOF
}

PROJECT="nexusshield-prod"
SA_NAME="epic6-operator-sa"
ROLES="roles/iam.serviceAccountUser,roles/storage.objectAdmin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --sa-name) SA_NAME="$2"; shift 2;;
    --roles) ROLES="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

echo "Project: $PROJECT, ServiceAccount: $SA_NAME"

# Ensure service account exists
if gcloud iam service-accounts describe "$SA_NAME@$PROJECT.iam.gserviceaccount.com" --project "$PROJECT" >/dev/null 2>&1; then
  echo "Service account exists"
else
  gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" --display-name "$SA_NAME"
  echo "Created service account $SA_NAME"
fi

# Bind roles (idempotent)
IFS=',' read -ra ROLE_ARR <<< "$ROLES"
for r in "${ROLE_ARR[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA_NAME@$PROJECT.iam.gserviceaccount.com" --role="$r" --quiet || true
done

# Create key and store in GSM
KEY_JSON=$(mktemp)
gcloud iam service-accounts keys create "$KEY_JSON" --iam-account "$SA_NAME@$PROJECT.iam.gserviceaccount.com" --project "$PROJECT"

SECRET_NAME="gcp-${SA_NAME}-key"
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud secrets versions add "$SECRET_NAME" --data-file="$KEY_JSON" --project="$PROJECT"
else
  gcloud secrets create "$SECRET_NAME" --data-file="$KEY_JSON" --project="$PROJECT"
fi

# Store to Vault if available
if command -v vault >/dev/null 2>&1; then
  vault kv put secret/gcp/epic6 key=@"$KEY_JSON" || true
fi

echo "Service account key stored in GSM as $SECRET_NAME and in Vault at secret/gcp/epic6"
rm -f "$KEY_JSON"
