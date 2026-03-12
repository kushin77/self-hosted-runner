#!/usr/bin/env bash
set -euo pipefail
# refresh-token.sh - obtain short-lived access token using creds.json
CREDS="$(dirname "$0")/creds.json"
OUT_DIR="/run/nexusshield"
OUT_FILE="$OUT_DIR/runner-access-token"
mkdir -p "$OUT_DIR"
if [ ! -f "$CREDS" ]; then
  echo "creds.json not found at $CREDS" >&2
  exit 2
fi
# Use gcloud to print an access token using the credential config
TOKEN=$(gcloud auth application-default print-access-token --credential-file-override="$CREDS")
if [ -z "$TOKEN" ]; then
  echo "Failed to obtain access token" >&2
  exit 3
fi
echo "$TOKEN" > "$OUT_FILE"
chmod 640 "$OUT_FILE"
echo "Wrote token to $OUT_FILE"
