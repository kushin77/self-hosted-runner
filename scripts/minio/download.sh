#!/usr/bin/env bash
set -euo pipefail

# Usage: download.sh --bucket <bucket> --object <key> --out <path>
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) BUCKET="$2"; shift 2;;
    --object) OBJECT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --endpoint) ENDPOINT="$2"; shift 2;;
    --access-key) ACCESS_KEY="$2"; shift 2;;
    --secret-key) SECRET_KEY="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

: "${BUCKET:?--bucket is required}"
: "${OBJECT:?--object is required}"
: "${OUT:?--out is required}"

ENDPOINT=${ENDPOINT:-${MINIO_ENDPOINT:-}}
ACCESS_KEY=${ACCESS_KEY:-${MINIO_ACCESS_KEY:-}}
SECRET_KEY=${SECRET_KEY:-${MINIO_SECRET_KEY:-}}

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
${MC_BIN} cp ${ALIAS_NAME}/${BUCKET}/${OBJECT} "$OUT"
echo "Downloaded ${ALIAS_NAME}/${BUCKET}/${OBJECT} to ${OUT}"
