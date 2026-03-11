#!/usr/bin/env bash

# Upload aggregated audit bundle to a secure artifact store (GCS or Azure Blob)
# Usage: tools/upload-aggregate.sh <aggregate.jsonl> [--provider gcs|azure]

set -euo pipefail

AGG_FILE="${1:-}"
PROVIDER="${2:-}"

if [ -z "$AGG_FILE" ]; then
  echo "Usage: $0 <aggregate.jsonl> [gcs|azure]" >&2
  exit 2
fi

if [ ! -f "$AGG_FILE" ]; then
  echo "Aggregate file not found: $AGG_FILE" >&2
  exit 3
fi

PROVIDER="${PROVIDER:-${UPLOAD_PROVIDER:-gcs}}"

case "$PROVIDER" in
  gcs)
    BUCKET="${GCS_BUCKET:-nexusshield-secret-audit}"
    DEST="gs://$BUCKET/$(basename "$AGG_FILE")"

    if ! command -v gsutil >/dev/null 2>&1; then
      echo "gsutil not found; install gcloud SDK or provide Azure provider" >&2
      exit 4
    fi

    # Ensure bucket exists (idempotent)
    if ! gsutil ls -b "gs://$BUCKET" >/dev/null 2>&1; then
      echo "Bucket gs://$BUCKET not found; creating..."
      gsutil mb -p "${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}" "gs://$BUCKET" || true
    fi

    # Upload only if object not present or different
    if gsutil -q stat "$DEST" >/dev/null 2>&1; then
      echo "Object already exists at $DEST; skipping upload";
    else
      echo "Uploading $AGG_FILE -> $DEST"
      gsutil cp "$AGG_FILE" "$DEST"
      echo "Uploaded to $DEST"
    fi
    ;;
  azure)
    CONTAINER="${AZURE_CONTAINER:-secret-audits}"
    ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"

    if ! command -v az >/dev/null 2>&1; then
      echo "az CLI not found; cannot upload to Azure Blob" >&2
      exit 4
    fi

    if [ -z "$ACCOUNT" ]; then
      echo "Set AZURE_STORAGE_ACCOUNT or configure provider" >&2
      exit 5
    fi

    # Create container if not exists
    if ! az storage container exists --name "$CONTAINER" --account-name "$ACCOUNT" --query "exists" -o tsv | grep -q true; then
      echo "Creating container $CONTAINER in account $ACCOUNT"
      az storage container create --name "$CONTAINER" --account-name "$ACCOUNT" >/dev/null
    fi

    # Upload (idempotent check)
    if az storage blob exists --container-name "$CONTAINER" --name "$(basename "$AGG_FILE")" --account-name "$ACCOUNT" --query "exists" -o tsv | grep -q true; then
      echo "Blob already exists in $ACCOUNT/$CONTAINER; skipping upload"
    else
      echo "Uploading $AGG_FILE to Azure Blob $CONTAINER"
      az storage blob upload --container-name "$CONTAINER" --file "$AGG_FILE" --name "$(basename "$AGG_FILE")" --account-name "$ACCOUNT" >/dev/null
      echo "Uploaded to azure://$ACCOUNT/$CONTAINER/$(basename "$AGG_FILE")"
    fi
    ;;
  *)
    echo "Unknown provider: $PROVIDER. Supported: gcs, azure" >&2
    exit 6
    ;;
esac

exit 0
