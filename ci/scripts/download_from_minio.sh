#!/usr/bin/env bash
set -euo pipefail

# download_from_minio.sh
# Usage: download_from_minio.sh <object-path> <dest-file>
# Expects MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET env vars.

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <object-path> <dest-file>" >&2
  exit 2
fi

OBJECT_PATH="$1"
DEST_FILE="$2"

if [[ -z "${MINIO_ENDPOINT-}" || -z "${MINIO_ACCESS_KEY-}" || -z "${MINIO_SECRET_KEY-}" || -z "${MINIO_BUCKET-}" ]]; then
  echo "ERROR: MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY and MINIO_BUCKET must be set" >&2
  exit 2
fi

if ! command -v mc >/dev/null 2>&1; then
  echo "mc client not found, installing to /tmp/mc"
  curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc > /tmp/mc && chmod +x /tmp/mc
  MC_BIN=/tmp/mc
else
  MC_BIN=mc
fi

ALIAS_NAME=minio-ci
"$MC_BIN" alias set "$ALIAS_NAME" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1

"$MC_BIN" cp "$ALIAS_NAME/$MINIO_BUCKET/$OBJECT_PATH" "$DEST_FILE"

echo "$DEST_FILE"
