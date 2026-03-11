#!/usr/bin/env bash
set -euo pipefail

# Usage:
# SUBJECT_TOKEN=... PROJECT_NUMBER=... WI_POOL=... WI_PROVIDER=... SA_EMAIL=... ./wrap-gcloud-with-wi.sh gcloud iam projects list

if [ "$#" -lt 1 ]; then
  echo "Usage: SUBJECT_TOKEN=... PROJECT_NUMBER=... WI_POOL=... WI_PROVIDER=... SA_EMAIL=... $0 <command...>" >&2
  exit 2
fi

cmd=("$@")

# Exchange and export token
token_json=$(PROJECT_NUMBER="$PROJECT_NUMBER" WI_POOL="$WI_POOL" WI_PROVIDER="$WI_PROVIDER" SA_EMAIL="$SA_EMAIL" SCOPES="$WI_SCOPES" SUBJECT_TOKEN="$SUBJECT_TOKEN" scripts/auth/exchange-wi-token.sh)
access_token=$(echo "$token_json" | jq -r .access_token // empty)
if [ -z "$access_token" ]; then
  echo "Failed to obtain access token" >&2
  echo "$token_json" >&2
  exit 3
fi

export CLOUDSDK_AUTH_ACCESS_TOKEN="$access_token"
unset GOOGLE_APPLICATION_CREDENTIALS || true

# Run the provided command with token in environment
"${cmd[@]}"
