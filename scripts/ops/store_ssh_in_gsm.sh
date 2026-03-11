#!/usr/bin/env bash
set -euo pipefail
# Store an SSH private key file into Google Secret Manager (idempotent)
# Usage: store_ssh_in_gsm.sh --project PROJECT --secret-name SECRET --file /path/to/key --member-sa SERVICE_ACCOUNT

usage(){
  cat <<EOF
Usage: $0 --project PROJECT --secret-name SECRET --file /path/to/private_key --member-sa SERVICE_ACCOUNT

Example:
  $0 --project nexusshield-prod --secret-name verifier-ssh-key --file /tmp/verifier_key --member-sa verifier-manager@PROJECT.iam.gserviceaccount.com
EOF
  exit 1
}

PROJECT=""
SECRET_NAME=""
KEY_FILE=""
MEMBER_SA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --secret-name) SECRET_NAME="$2"; shift 2;;
    --file) KEY_FILE="$2"; shift 2;;
    --member-sa) MEMBER_SA="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$PROJECT" || -z "$SECRET_NAME" || -z "$KEY_FILE" || -z "$MEMBER_SA" ]]; then
  usage
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Key file not found: $KEY_FILE" >&2
  exit 2
fi

set -x
if gcloud secrets describe "$SECRET_NAME" --project "$PROJECT" >/dev/null 2>&1; then
  echo "Secret $SECRET_NAME already exists in project $PROJECT, adding new version"
  gcloud secrets versions add "$SECRET_NAME" --data-file="$KEY_FILE" --project="$PROJECT"
else
  echo "Creating secret $SECRET_NAME in project $PROJECT"
  gcloud secrets create "$SECRET_NAME" --data-file="$KEY_FILE" --replication-policy="automatic" --project="$PROJECT"
fi

echo "Granting access to $MEMBER_SA"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" --project "$PROJECT" --member="serviceAccount:$MEMBER_SA" --role="roles/secretmanager.secretAccessor"

echo "Stored SSH key as secret: projects/$PROJECT/secrets/$SECRET_NAME"
exit 0
