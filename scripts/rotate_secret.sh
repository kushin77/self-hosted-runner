#!/usr/bin/env bash
set -euo pipefail

# Simple helper to create a new secret version in GSM from stdin
# Usage: echo -n "new-secret-value" | scripts/rotate_secret.sh secrets/SECRET_ID

if [ "$#" -ne 1 ]; then
  echo "Usage: rotate_secret.sh <secret_id>" >&2
  exit 2
fi

SECRET_ID="$1"

if [ -t 0 ]; then
  echo "Reading new secret value from stdin..." >&2
fi

gsutil_version_check() {
  command -v gcloud >/dev/null 2>&1 || { echo "gcloud not installed" >&2; exit 3; }
}

gsutil_version_check

# Read secret from stdin
SECRET_DATA=$(cat -)

printf "%s" "$SECRET_DATA" | gcloud secrets versions add "$SECRET_ID" --data-file=-

echo "New secret version created for $SECRET_ID"
