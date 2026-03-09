#!/usr/bin/env bash
# Forward deploy-audit.log to MinIO/S3-compatible storage (optional)
set -euo pipefail

AUDIT_FILE="${1:-/home/akushnir/self-hosted-runner/deploy-audit.log}"
DEST_BUCKET="${MINIO_AUDIT_BUCKET:-deploy-audit}" 
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://127.0.0.1:9000}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-}" 
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-}"

if [[ ! -f "$AUDIT_FILE" ]]; then
  echo "No audit file at $AUDIT_FILE; nothing to forward." >&2
  exit 0
fi

if [[ -z "$MINIO_ACCESS_KEY" || -z "$MINIO_SECRET_KEY" ]]; then
  echo "MinIO credentials not provided; skipping forward." >&2
  exit 0
fi

if ! command -v mc >/dev/null 2>&1; then
  echo "mc (MinIO client) not found; skipping forward." >&2
  exit 0
fi

# Configure temporary alias
mc alias set ops-minio "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1 || true

# Ensure bucket exists
mc mb --ignore-existing ops-minio/$DEST_BUCKET >/dev/null 2>&1 || true

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST_KEY="deploy-audit-$TIMESTAMP.log"

mc cp "$AUDIT_FILE" ops-minio/$DEST_BUCKET/$DEST_KEY || {
  echo "Failed to upload audit to MinIO" >&2
  exit 1
}

echo "Audit forwarded to ops-minio/$DEST_BUCKET/$DEST_KEY"
exit 0
