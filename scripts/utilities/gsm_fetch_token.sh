#!/usr/bin/env bash
set -euo pipefail
# Fetch a secret from Google Secret Manager and write GH_TOKEN to stdout or file
# Usage: gsm_fetch_token.sh projects/PROJECT/secrets/SECRET/versions/latest /path/to/out

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <secret_name> [out_file]" >&2
  exit 2
fi
SECRET_NAME="$1"
OUT_FILE="${2:-}" 

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not installed; cannot fetch from GSM" >&2
  exit 1
fi

TOKEN=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --format='get(payload.data)' | tr '_-' '/+' | base64 --decode)

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf '%s' "$TOKEN" > "$OUT_FILE"
  chmod 600 "$OUT_FILE"
else
  printf '%s' "$TOKEN"
fi
