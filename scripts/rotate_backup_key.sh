#!/usr/bin/env bash
set -euo pipefail

# Rotate the nexusshield-tfstate-backup service account key.
# - Creates a new key for the SA
# - Adds it as a new version to Secret Manager secret `nexusshield-tfstate-backup-key`
# - Fetches the latest secret to the runner path `/home/akushnir/.credentials/nexusshield-tfstate-backup-key.json`
# Note: This script does NOT delete old keys automatically. Review and delete old keys manually.

SA_EMAIL="nexusshield-tfstate-backup@nexusshield-prod.iam.gserviceaccount.com"
SECRET_NAME="nexusshield-tfstate-backup-key"
LOCAL_KEY_PATH="/tmp/nexusshield-tfstate-backup-key.new.json"
RUNNER_KEY_PATH="/home/akushnir/.credentials/nexusshield-tfstate-backup-key.json"

echo "Rotating key for ${SA_EMAIL}..."

# Require terraform-deployer creds to be set via GOOGLE_APPLICATION_CREDENTIALS
if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  echo "Set GOOGLE_APPLICATION_CREDENTIALS to the terraform service account key file and retry." >&2
  exit 2
fi

gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set project nexusshield-prod

echo "Creating new service account key..."
gcloud iam service-accounts keys create "$LOCAL_KEY_PATH" --iam-account="$SA_EMAIL"

echo "Uploading new key as secret version to Secret Manager ($SECRET_NAME)..."
if gcloud secrets describe "$SECRET_NAME" >/dev/null 2>&1; then
  gcloud secrets versions add "$SECRET_NAME" --data-file="$LOCAL_KEY_PATH"
else
  gcloud secrets create "$SECRET_NAME" --replication-policy="automatic" --data-file="$LOCAL_KEY_PATH"
fi

echo "Copying new key to runner path ($RUNNER_KEY_PATH) for backup job..."
mkdir -p "$(dirname "$RUNNER_KEY_PATH")"
gcloud secrets versions access latest --secret="$SECRET_NAME" > "$RUNNER_KEY_PATH"
chmod 600 "$RUNNER_KEY_PATH"
chown $(id -u):$(id -g) "$RUNNER_KEY_PATH" || true

echo "Cleanup: removing local temp key file"
rm -f "$LOCAL_KEY_PATH"

echo "Rotation complete. New key is stored as latest version of secret $SECRET_NAME and copied to $RUNNER_KEY_PATH"
echo "NOTE: review and delete old SA keys when appropriate with: gcloud iam service-accounts keys list --iam-account=$SA_EMAIL"
