#!/usr/bin/env bash
set -euo pipefail

# Usage: upload.sh --file <path> --bucket <bucket> --object <key>
FILE=""
BUCKET=""
OBJECT=""
ENDPOINT=${MINIO_ENDPOINT:-}
ACCESS_KEY=${MINIO_ACCESS_KEY:-}
SECRET_KEY=${MINIO_SECRET_KEY:-}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2;;
    --bucket) BUCKET="$2"; shift 2;;
    --object) OBJECT="$2"; shift 2;;
    --endpoint) ENDPOINT="$2"; shift 2;;
    --access-key) ACCESS_KEY="$2"; shift 2;;
    --secret-key) SECRET_KEY="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [ -z "$FILE" ]; then echo "Error: --file is required"; exit 2; fi
if [ -z "$BUCKET" ]; then echo "Error: --bucket is required"; exit 2; fi
if [ -z "$OBJECT" ]; then echo "Error: --object is required"; exit 2; fi

if [ -z "$ENDPOINT" ] || [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "MINIO_ENDPOINT, MINIO_ACCESS_KEY and MINIO_SECRET_KEY must be set (or pass via --endpoint/--access-key/--secret-key)" >&2
  exit 2
fi

INSTALLER="$(dirname "$0")/install-mc.sh"
chmod +x "$INSTALLER"
"$INSTALLER"

MC_BIN=${MC_BIN:-/usr/local/bin/mc}
ALIAS_NAME=${MINIO_ALIAS:-ci-minio}

${MC_BIN} alias set ${ALIAS_NAME} "${ENDPOINT}" "${ACCESS_KEY}" "${SECRET_KEY}" --api S3v4
${MC_BIN} mb --ignore-existing ${ALIAS_NAME}/${BUCKET}
${MC_BIN} cp "$FILE" ${ALIAS_NAME}/${BUCKET}/${OBJECT}
echo "Uploaded ${FILE} to ${ENDPOINT}/${BUCKET}/${OBJECT}"
