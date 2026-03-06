#!/usr/bin/env bash
set -euo pipefail

# prune_backups.sh
# Removes old backup objects from S3 keeping the most recent N copies.

usage(){
  cat <<EOF
Usage: S3_BUCKET=s3://bucket/path KEEP=7 ./scripts/backup/prune_backups.sh

Environment:
  S3_BUCKET - s3://... required
  KEEP      - number of latest backups to keep (default 7)
  AWS_PROFILE/AWS_REGION - optional

Requires `aws` CLI configured with access to the bucket.
EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then usage; exit 0; fi

S3_BUCKET=${S3_BUCKET:-}
KEEP=${KEEP:-7}
if [ -z "$S3_BUCKET" ]; then echo "S3_BUCKET required"; usage; exit 2; fi

echo "Listing objects under $S3_BUCKET"
OBJ_LIST=$(aws s3 ls "$S3_BUCKET/" --recursive | awk '{print $4}' | sort -r)

COUNT=0
for obj in $OBJ_LIST; do
  COUNT=$((COUNT+1))
  if [ $COUNT -le $KEEP ]; then
    echo "Keeping: $obj"
  else
    echo "Deleting: $obj"
    aws s3 rm "${S3_BUCKET%/}/$obj" || true
  fi
done

echo "Prune complete. Kept $KEEP objects."
