#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Local secrets health check wrapper
# Runs the unified secret mirror in local mode (dry-run by default)
# Produces artifacts under logs/secret-mirror and logs/local-health
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs/local_secrets_health"
MIRROR_SCRIPT="$ROOT_DIR/scripts/secrets/mirror-all-backends.sh"

DRY_RUN=1
if [ "${1:-}" = "--apply" ] || [ "${APPLY:-}" = "1" ]; then
    DRY_RUN=0
fi

mkdir -p "$LOG_DIR"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUT_LOG="$LOG_DIR/health-run-${TIMESTAMP}.log"
ARTIFACT_DIR="$ROOT_DIR/logs/secret-mirror"
mkdir -p "$ARTIFACT_DIR"

echo "Local secrets health check starting at $(date -u)" | tee "$OUT_LOG"

if [ ! -x "$MIRROR_SCRIPT" ]; then
    echo "Mirror script not executable; attempting to run with bash." | tee -a "$OUT_LOG"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN mode: running mirror script without writes" | tee -a "$OUT_LOG"
    bash "$MIRROR_SCRIPT" 2>&1 | tee -a "$OUT_LOG"
else
    echo "APPLY mode: running mirror script with --apply" | tee -a "$OUT_LOG"
    bash "$MIRROR_SCRIPT" --apply 2>&1 | tee -a "$OUT_LOG"
fi

# Collect any generated audit files into this run-specific folder
RUN_ARTIFACT_DIR="$ARTIFACT_DIR/run-${TIMESTAMP}"
mkdir -p "$RUN_ARTIFACT_DIR"
cp -a "$ARTIFACT_DIR"/mirror-*.jsonl "$RUN_ARTIFACT_DIR/" 2>/dev/null || true
cp -a "$ARTIFACT_DIR"/encrypted-* "$RUN_ARTIFACT_DIR/" 2>/dev/null || true
cp "$OUT_LOG" "$RUN_ARTIFACT_DIR/" || true

echo "Local health check complete. Artifacts: $RUN_ARTIFACT_DIR" | tee -a "$OUT_LOG"

exit 0
