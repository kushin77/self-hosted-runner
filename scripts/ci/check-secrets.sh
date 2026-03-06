#!/usr/bin/env bash
set -euo pipefail

missing=()

require() {
  name="$1"
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  fi
}

require MINIO_ENDPOINT
require MINIO_ACCESS_KEY
require MINIO_SECRET_KEY
require MINIO_BUCKET

if [ ${#missing[@]} -ne 0 ]; then
  echo "ERROR: Missing required secrets/env vars:" >&2
  for m in "${missing[@]}"; do
    echo "  - $m" >&2
  done
  echo "Please add them to the repository secrets and re-run this workflow." >&2
  exit 2
fi

echo "All required MinIO secrets are present. Continuing..."
