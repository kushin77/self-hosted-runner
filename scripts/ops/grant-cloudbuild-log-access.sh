#!/usr/bin/env bash
set -euo pipefail

# Usage:
#  BUCKET_NAME=your-bucket ./scripts/ops/grant-cloudbuild-log-access.sh
# This grants objectViewer on the specified bucket to the deployer-run service account.

BUCKET_NAME=${BUCKET_NAME:-}
if [ -z "$BUCKET_NAME" ]; then
  echo "Usage: BUCKET_NAME=your-bucket $0" >&2
  exit 2
fi

SA="deployer-run@nexusshield-prod.iam.gserviceaccount.com"

echo "Granting roles/storage.objectViewer on gs://$BUCKET_NAME to $SA"

# bucket-level least-privilege grant
if ! gsutil iam ch "serviceAccount:$SA:objectViewer" "gs://$BUCKET_NAME"; then
  echo "gsutil iam ch failed" >&2
  exit 1
fi

echo "Done. Verify with: gsutil iam get gs://$BUCKET_NAME | grep $SA || true"