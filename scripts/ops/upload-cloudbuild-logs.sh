#!/usr/bin/env bash
set -euo pipefail

# Usage:
#  BUILD_ID=20cb859f-8545-40ec-9899-2990723f85b5 BUCKET=gs://projects/_/logs/my-cloudbuild-logs ./scripts/ops/upload-cloudbuild-logs.sh
# This script finds objects matching BUILD_ID under BUCKET and copies them to DEST_DIR (defaults to ./cloudbuild-logs)

BUILD_ID=${BUILD_ID:-}
BUCKET=${BUCKET:-}
DEST_DIR=${DEST_DIR:-./cloudbuild-logs}

if [ -z "$BUILD_ID" ] || [ -z "$BUCKET" ]; then
  echo "Usage: BUILD_ID=<id> BUCKET=gs://... [DEST_DIR=./cloudbuild-logs] $0" >&2
  exit 2
fi

mkdir -p "$DEST_DIR"

echo "Searching for objects in $BUCKET matching $BUILD_ID..."

# Use gsutil to list; requires permission to list or read
# Note: '**' requires wildcard support in some gsutil versions; fallback to listing bucket root
OBJECTS=$(gsutil ls "$BUCKET/**" 2>/dev/null || gsutil ls "$BUCKET/" 2>/dev/null | grep "$BUILD_ID" || true)

if [ -z "$OBJECTS" ]; then
  echo "No objects found matching $BUILD_ID in $BUCKET" >&2
  exit 1
fi

echo "Found objects:"
printf "%s
" "$OBJECTS"

for obj in $OBJECTS; do
  echo "Copying $obj to $DEST_DIR/"
  gsutil cp "$obj" "$DEST_DIR/" || echo "Failed to copy $obj"
done

echo "All done. Logs available in $DEST_DIR"