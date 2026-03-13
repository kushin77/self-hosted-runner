#!/usr/bin/env bash
# Runner wrapper for milestone report generator
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIF="${CLASSIFICATION_FILE:-$ROOT_DIR/artifacts/milestones-assignments/classification.json}"
ARTIFACT_DIR="${REPORT_ARTIFACT_DIR:-$ROOT_DIR/artifacts/reports}"
mkdir -p "$ARTIFACT_DIR"

# If REPORT_GCS_BUCKET_REF is a gsm:// ref, resolve it via gcloud
if [ -n "${REPORT_GCS_BUCKET_REF:-}" ]; then
  if [[ "$REPORT_GCS_BUCKET_REF" == gsm://* ]]; then
    secret_name=${REPORT_GCS_BUCKET_REF#gsm://}
    if command -v gcloud >/dev/null 2>&1; then
      export REPORT_GCS_BUCKET=$(gcloud secrets versions access latest --secret="$secret_name" 2>/dev/null || true)
    fi
  else
    export REPORT_GCS_BUCKET="$REPORT_GCS_BUCKET_REF"
  fi
fi

export REPORT_ARTIFACT_DIR="$ARTIFACT_DIR"

PYTHON="${PYTHON:-python3}"
SCRIPT="$ROOT_DIR/scripts/monitoring/report_generator.py"

echo "Running report generator with classification file: $CLASSIF"
"$PYTHON" "$SCRIPT" "$CLASSIF" "$ARTIFACT_DIR/milestone-organizer-report.html"
