#!/usr/bin/env bash
set -euo pipefail
# Simple monitor: list latest objects in artifacts bucket
BUCKET=${1:-nexusshield-prod-artifacts}
PREFIX=${2:-}
echo "Listing latest objects in gs://${BUCKET}/${PREFIX}"
if ! command -v gsutil >/dev/null 2>&1; then
  echo "gsutil not found in PATH" >&2
  exit 2
fi
if [[ -n "$PREFIX" ]]; then
  gsutil ls -l "gs://${BUCKET}/${PREFIX}/**" 2>/dev/null | tail -n 50 || gsutil ls -l "gs://${BUCKET}/${PREFIX}" 2>/dev/null || true
else
  gsutil ls -l "gs://${BUCKET}/**" 2>/dev/null | tail -n 50 || gsutil ls -l "gs://${BUCKET}" 2>/dev/null || true
fi
echo "Done."
