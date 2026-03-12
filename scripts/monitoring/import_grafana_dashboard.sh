#!/usr/bin/env bash
set -euo pipefail

# Usage: GRAFANA_URL=https://grafana.example.com GRAFANA_API_KEY=ey... ./scripts/monitoring/import_grafana_dashboard.sh monitoring/dashboards/canonical_secrets_dashboard.json

if [ "$#" -ne 1 ]; then
  echo "Usage: GRAFANA_URL=... GRAFANA_API_KEY=... $0 <dashboard-json-file>" >&2
  exit 2
fi

DASHBOARD_FILE="$1"

GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"

if [ -z "$GRAFANA_URL" ] || [ -z "$GRAFANA_API_KEY" ]; then
  echo "Error: GRAFANA_URL and GRAFANA_API_KEY must be set in environment." >&2
  exit 2
fi

if [ ! -f "$DASHBOARD_FILE" ]; then
  echo "Error: dashboard file not found: $DASHBOARD_FILE" >&2
  exit 2
fi

TMP_PAYLOAD="/tmp/grafana_dashboard_payload_$$.json"
jq -n --argfile d "$DASHBOARD_FILE" '{dashboard: $d.dashboard, overwrite: true}' > "$TMP_PAYLOAD"

HTTP_STATUS=$(curl -s -w "%{http_code}" -o /tmp/grafana_import_response.json \
  -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary @"$TMP_PAYLOAD")

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "Success: dashboard imported (HTTP $HTTP_STATUS)"
  jq '.' /tmp/grafana_import_response.json
  rm -f "$TMP_PAYLOAD" /tmp/grafana_import_response.json
  exit 0
else
  echo "Failed to import dashboard (HTTP $HTTP_STATUS)" >&2
  jq '.' /tmp/grafana_import_response.json >&2 || cat /tmp/grafana_import_response.json >&2
  rm -f "$TMP_PAYLOAD" /tmp/grafana_import_response.json
  exit 3
fi
