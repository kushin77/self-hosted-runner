#!/bin/bash
# upload_diagnostics.sh - collect diagnostic bundle and upload to GCS every 6 hours (4 iterations = 24h)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_BUCKET="gs://nexusshield-prod-daily-summaries-151423364222/compliance-archives"
LABEL="diagnostic-bundle"
ITERATIONS=4
SLEEP_SECS=$((6 * 3600))

mkdir -p "$ROOT_DIR/logs/automation-manager"

for i in $(seq 1 "$ITERATIONS"); do
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  TAR_NAME="${LABEL}-${TS}.tar.gz"
  TMPDIR=$(mktemp -d)
  echo "[diagnostics] Creating bundle $TAR_NAME (iteration $i/$ITERATIONS)"
  tar -czf "$TMPDIR/$TAR_NAME" -C "$ROOT_DIR" logs/stabilization-monitor logs/epic-2-migration logs/epic-3-aws-migration logs/epic-4-azure-migration || true
  if command -v gsutil >/dev/null 2>&1; then
    echo "[diagnostics] Uploading $TAR_NAME to $OUT_BUCKET"
    gsutil cp "$TMPDIR/$TAR_NAME" "$OUT_BUCKET/diagnostic-bundles/" >/dev/null 2>&1 || echo "[diagnostics] Upload failed for $TAR_NAME"
    echo "$(date -u) Uploaded $TAR_NAME" >> "$ROOT_DIR/logs/automation-manager/diagnostics.log"
  else
    echo "[diagnostics] gsutil not available; skipping upload" >> "$ROOT_DIR/logs/automation-manager/diagnostics.log"
  fi
  rm -rf "$TMPDIR"
  if [ "$i" -lt "$ITERATIONS" ]; then
    sleep "$SLEEP_SECS"
  fi
done

echo "[diagnostics] Completed $ITERATIONS iterations; exiting"
