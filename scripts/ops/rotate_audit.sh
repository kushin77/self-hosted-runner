#!/usr/bin/env bash
set -euo pipefail
# Rotate portal audit JSONL when size exceeds threshold and upload to GCS
AUDIT_FILE=${AUDIT_FILE:-/opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl}
ROT_DIR=${ROT_DIR:-/opt/nexusshield/scripts/cloudrun/logs/rotated}
BUCKET=${GCS_AUDIT_BUCKET:-nexusshield-audit-archive}
THRESHOLD=${THRESHOLD_BYTES:-104857600} # 100MB

if [ ! -f "$AUDIT_FILE" ]; then
  echo "No audit file found at $AUDIT_FILE" >&2
  exit 0
fi

size=$(stat -c%s "$AUDIT_FILE")
if [ "$size" -lt "$THRESHOLD" ]; then
  echo "Audit file size $size < $THRESHOLD; skipping rotation"
  exit 0
fi

mkdir -p "$ROT_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
BASENAME="portal-migrate-audit-${TS}.jsonl"
mv "$AUDIT_FILE" "$ROT_DIR/$BASENAME"
gzip -9 "$ROT_DIR/$BASENAME"

echo "Uploading $ROT_DIR/$BASENAME.gz to gs://$BUCKET/$TS/"
if command -v gsutil >/dev/null 2>&1; then
  gsutil cp "$ROT_DIR/$BASENAME.gz" "gs://$BUCKET/$TS/"
else
  echo "gsutil not found; skipping upload" >&2
fi

# Recreate an empty audit file with proper permissions
mkdir -p "$(dirname "$AUDIT_FILE")"
touch "$AUDIT_FILE"
chown root:root "$AUDIT_FILE" || true
chmod 644 "$AUDIT_FILE" || true

echo "Rotation complete: $ROT_DIR/$BASENAME.gz"
