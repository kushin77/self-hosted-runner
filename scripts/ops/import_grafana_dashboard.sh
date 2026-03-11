#!/usr/bin/env bash
set -euo pipefail

# Import/overwrite Grafana dashboard JSON using Grafana HTTP API and GSM secrets
# Requires either environment variables `GRAFANA_URL` and `GRAFANA_API_KEY` set,
# or secrets `grafana-url` and `grafana-api-key` present in Google Secret Manager.

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
GRAFANA_URL=${GRAFANA_URL:-}
GRAFANA_API_KEY=${GRAFANA_API_KEY:-}

if [ -z "$GRAFANA_URL" ]; then
  if [ -n "$PROJECT" ]; then
    GRAFANA_URL=$(gcloud secrets versions access latest --secret=grafana-url --project="$PROJECT" 2>/dev/null || true)
  fi
fi
if [ -z "$GRAFANA_API_KEY" ]; then
  if [ -n "$PROJECT" ]; then
    GRAFANA_API_KEY=$(gcloud secrets versions access latest --secret=grafana-api-key --project="$PROJECT" 2>/dev/null || true)
  fi
fi

if [ -z "$GRAFANA_URL" ] || [ -z "$GRAFANA_API_KEY" ]; then
  echo "GRAFANA_URL or GRAFANA_API_KEY not provided (env or GSM)." >&2
  exit 1
fi

DASH_FILE="$(dirname "$0")/../../dashboards/nexusshield.json"
if [ ! -f "$DASH_FILE" ]; then
  echo "Dashboard file not found: $DASH_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found; please install jq to use this script" >&2
  exit 1
fi

echo "Importing dashboard to Grafana: $GRAFANA_URL"
body=$(jq -c -n --argfile d "$DASH_FILE" '{dashboard: $d, overwrite: true}')

curl -sS -H "Content-Type: application/json" -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -X POST "$GRAFANA_URL/api/dashboards/db" -d "$body" | jq .
