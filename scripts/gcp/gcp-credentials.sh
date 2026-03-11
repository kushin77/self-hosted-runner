#!/usr/bin/env bash
set -euo pipefail

# Runtime GCP credential fetcher: GSM -> Vault -> write keyfile and set GOOGLE_APPLICATION_CREDENTIALS

PROJECT="nexusshield-prod"
SECRET_NAME="gcp-epic6-operator-sa-key"

fetch_from_gsm(){
  local s="$1"
  gcloud secrets versions access latest --secret="$s" --project="$PROJECT" 2>/dev/null || true
}

KEY_JSON=$(mktemp --suffix=.json)
candidate=$(fetch_from_gsm "$SECRET_NAME" || true)
if [ -n "$candidate" ]; then
  echo "$candidate" > "$KEY_JSON"
else
  if command -v vault >/dev/null 2>&1; then
    vault kv get -field=key secret/gcp/epic6 > "$KEY_JSON" 2>/dev/null || true
  fi
fi

if [ -s "$KEY_JSON" ]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$KEY_JSON"
  echo "GCP credentials written to $GOOGLE_APPLICATION_CREDENTIALS"
else
  rm -f "$KEY_JSON"
  echo "No GCP service account key found in GSM or Vault" >&2
  exit 1
fi
