#!/usr/bin/env bash
set -euo pipefail

# Rotate the append-only audit log, verify chain, upload to configured bucket, and archive locally.

AUDIT_LOG=${PORTAL_AUDIT_LOG:-logs/portal-migrate-audit.jsonl}
ARCHIVE_DIR=${AUDIT_ARCHIVE_DIR:-logs/archive}
VERIFY_PY=${VERIFY_PY:-$(dirname "$0")/audit_verify.py}
UPLOAD_PY=${UPLOAD_PY:-$(dirname "$0")/upload_audit.py}

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
rotated="$ARCHIVE_DIR/audit-$timestamp.jsonl"

mkdir -p "$ARCHIVE_DIR"

if [ ! -f "$AUDIT_LOG" ]; then
  echo "No audit log found at $AUDIT_LOG"
  exit 0
fi

echo "Rotating audit log to $rotated"
mv "$AUDIT_LOG" "$rotated"

# Create a fresh audit log placeholder
mkdir -p "$(dirname "$AUDIT_LOG")"
echo "" > "$AUDIT_LOG"

echo "Verifying chain for $rotated"
python3 "$VERIFY_PY" "$rotated"
rc=$?
if [ $rc -ne 0 ]; then
  echo "Audit chain verification failed for $rotated" >&2
  exit $rc
fi

echo "Uploading $rotated"
python3 "$UPLOAD_PY" "$rotated"
rc=$?
if [ $rc -ne 0 ]; then
  echo "Upload failed for $rotated" >&2
  exit $rc
fi

echo "Compressing local archive"
gzip -9 "$rotated"
echo "Rotation and upload complete: $rotated.gz"
