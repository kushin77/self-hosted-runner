#!/usr/bin/env bash
set -euo pipefail

# import_to_grafana.sh
# Imports a Grafana dashboard JSON to a running Grafana instance via HTTP API.
# Usage: import_to_grafana.sh <grafana_url> <dashboard_json_file> [api_key]

GRAFANA_URL=${1:-}
DASHBOARD_FILE=${2:-}
API_KEY=${3:-}

if [[ -z "$GRAFANA_URL" || -z "$DASHBOARD_FILE" ]]; then
  echo "Usage: $0 <grafana_url> <dashboard_json_file> [api_key]"
  exit 2
fi

if [[ ! -f "$DASHBOARD_FILE" ]]; then
  echo "Dashboard file not found: $DASHBOARD_FILE" >&2
  exit 1
fi

if [[ -n "$API_KEY" ]]; then
  AUTH_HEADER="Authorization: Bearer $API_KEY"
else
  # default to basic admin:admin for local test containers
  AUTH_HEADER="-u admin:admin"
fi

payload=$(jq -c '{dashboard: input, overwrite: true}' < "$DASHBOARD_FILE")

if [[ -n "$API_KEY" ]]; then
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -H "$AUTH_HEADER" -d "$payload" "$GRAFANA_URL/api/dashboards/db")
else
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" $AUTH_HEADER -d "$payload" "$GRAFANA_URL/api/dashboards/db")
fi

if [[ "$status" =~ ^2 ]]; then
  echo "Dashboard import succeeded (HTTP $status)"
  exit 0
else
  echo "Dashboard import failed (HTTP $status)" >&2
  exit 3
fi
