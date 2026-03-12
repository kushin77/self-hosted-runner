Import dashboard now

If you have access to the Grafana instance, run this locally (replace values):

```bash
export GRAFANA_URL="https://grafana.example.com"
export GRAFANA_API_KEY="<SHORT_LIVED_KEY>"
./scripts/monitoring/import_grafana_dashboard.sh monitoring/dashboards/canonical_secrets_dashboard.json
```

If you prefer a single curl command (no jq):

```bash
PAYLOAD=$(printf '{"dashboard":%s, "overwrite":true}' "$(cat monitoring/dashboards/canonical_secrets_dashboard.json | sed "$ s/\\$/\\n/")")
curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD" | jq '.'
```

Notes:
- The import requires a Grafana API key with `dashboards:write` scope.
- I can run the import if you provide `GRAFANA_URL` and a short-lived `GRAFANA_API_KEY`, or you can run the commands above locally.
