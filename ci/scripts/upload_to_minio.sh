#!/usr/bin/env bash
set -euo pipefail

# upload_to_minio.sh
# Upload a file to MinIO using the `mc` client. Expects MINIO_ENDPOINT, MINIO_ACCESS_KEY,
# MINIO_SECRET_KEY and MINIO_BUCKET to be provided via env. Does not print secrets.

usage(){
  cat <<EOF
Usage: $0 <file> [object-path]
Environment required: MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

FILE="$1"
OBJECT_PATH="${2:-sealed/$(date +%s)-$(basename "$FILE") }"

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

# Configure alias (do not print credentials)
"$MC_BIN" alias set "$ALIAS_NAME" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1

# Create bucket if not exists
"$MC_BIN" mb --ignore-existing "$ALIAS_NAME/$MINIO_BUCKET" >/dev/null 2>&1 || true

# Upload file
"$MC_BIN" cp "$FILE" "$ALIAS_NAME/$MINIO_BUCKET/$OBJECT_PATH"

# Generate object URL (assumes bucket is accessible via endpoint)
URL="${MINIO_ENDPOINT%/}/${MINIO_BUCKET}/${OBJECT_PATH}"

echo "$URL"
