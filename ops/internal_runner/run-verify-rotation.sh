#!/usr/bin/env bash
set -euo pipefail

# Wrapper for nightly verify-rotation job
ROOT_DIR="/home/akushnir/self-hosted-runner"
SCRIPT="$ROOT_DIR/scripts/tests/verify-rotation.sh"
LOG_BUCKET="gs://nexusshield-ops-logs/verify-rotation"
LOG_FILE="$ROOT_DIR/ops/internal_runner/verify-rotation-$(date +%F).log"

export PROJECT=${PROJECT:-nexusshield-prod}

echo "[run-verify-rotation] starting at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$LOG_FILE"

# Run verification script
"$SCRIPT" >> "$LOG_FILE" 2>&1 || {
  echo "[run-verify-rotation] verify script failed" >> "$LOG_FILE"
  gsutil cp "$LOG_FILE" "$LOG_BUCKET/" || true
  exit 2
}

# Upload log
gsutil cp "$LOG_FILE" "$LOG_BUCKET/" || true

echo "[run-verify-rotation] completed at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$LOG_FILE"
