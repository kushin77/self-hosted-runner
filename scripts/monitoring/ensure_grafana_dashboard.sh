#!/usr/bin/env bash
set -euo pipefail

# Idempotent: import the Canonical Secrets Grafana dashboard if it doesn't exist.
# Usage (deployment hook):
#   GRAFANA_URL=... GRAFANA_API_KEY=... ./scripts/monitoring/ensure_grafana_dashboard.sh

GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"
DASHBOARD_FILE="monitoring/dashboards/canonical_secrets_dashboard.json"

if [ -z "$GRAFANA_URL" ] || [ -z "$GRAFANA_API_KEY" ]; then
  echo "Skipping Grafana import: GRAFANA_URL or GRAFANA_API_KEY not set." >&2
  exit 0
fi

if [ ! -f "$DASHBOARD_FILE" ]; then
  echo "Dashboard file missing: $DASHBOARD_FILE" >&2
  exit 2
fi

echo "Checking Grafana for existing dashboard 'Canonical Secrets API Monitoring'..."
RESULT=$(curl -s -G "$GRAFANA_URL/api/search" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  --data-urlencode "query=Canonical Secrets API Monitoring")

if echo "$RESULT" | grep -q 'Canonical Secrets API Monitoring'; then
  echo "Dashboard already present in Grafana; skipping import."
  exit 0
fi

echo "Dashboard not found — importing now..."
./scripts/monitoring/import_grafana_dashboard.sh "$DASHBOARD_FILE"

echo "Import completed."
