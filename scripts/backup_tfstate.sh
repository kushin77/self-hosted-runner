#!/usr/bin/env bash
set -euo pipefail

# Simple script to upload local terraform.tfstate to GCS with timestamp
# Usage: scripts/backup_tfstate.sh /path/to/terraform.tfstate

TFSTATE_PATH="${1:-./nexusshield/infrastructure/terraform/production/terraform.tfstate}"
BUCKET="nexusshield-terraform-state-backups"

KEY_FILE="${BACKUP_SA_KEY_FILE:-/home/akushnir/.credentials/nexusshield-tfstate-backup-key.json}"

if [ ! -f "$TFSTATE_PATH" ]; then
  echo "tfstate not found at $TFSTATE_PATH" >&2
  exit 2
fi

# If a backup service account key file exists, activate it for gsutil access.
if [ -f "$KEY_FILE" ]; then
  echo "Activating backup service account from $KEY_FILE"
  gcloud auth activate-service-account --key-file="$KEY_FILE"
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)
DEST="gs://$BUCKET/production/terraform.tfstate.$TS"

echo "Uploading $TFSTATE_PATH -> $DEST"
gsutil cp "$TFSTATE_PATH" "$DEST"

echo "Upload complete: $DEST"

# Optionally: write a 'latest' pointer
gsutil cp "$TFSTATE_PATH" "gs://$BUCKET/production/terraform.tfstate.latest"

echo "Updated latest pointer"
