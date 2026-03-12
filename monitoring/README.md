## Monitoring: Grafana dashboard import

This folder contains generated Grafana dashboards for the Canonical Secrets system.

Files:
- `dashboards/canonical_secrets_dashboard.json` — generated dashboard JSON (ready for import).

Import quick start (recommended):

1. Ensure `jq` and `curl` are installed.
2. Set environment variables for your Grafana instance:

```bash
export GRAFANA_URL="https://grafana.example.com"
export GRAFANA_API_KEY="<your_grafana_api_key>"
```

3. Run the included import script:

```bash
GRAFANA_URL="$GRAFANA_URL" GRAFANA_API_KEY="$GRAFANA_API_KEY" \
  ./scripts/monitoring/import_grafana_dashboard.sh monitoring/dashboards/canonical_secrets_dashboard.json
```

Manual import (Grafana UI):
1. In Grafana, go to Dashboards → Import.
2. Upload `monitoring/dashboards/canonical_secrets_dashboard.json`.
3. Choose the Prometheus datasource used by the Canonical Secrets monitoring.

If you want, I can attempt the import now — provide `GRAFANA_URL` and a short-lived `GRAFANA_API_KEY`, or allow me to run it if credentials are configured on this machine.

Automate on deploy
------------------

To import the dashboard automatically on first deployment, add the following deployment hook or CI step after your Grafana credentials are available:

```bash
# Example deployment hook (idempotent)
GRAFANA_URL="https://grafana.example.com" \
GRAFANA_API_KEY="${GRAFANA_API_KEY}" \
  ./scripts/monitoring/ensure_grafana_dashboard.sh
```

The `ensure_grafana_dashboard.sh` script checks whether a dashboard named "Canonical Secrets API Monitoring" already exists and only imports if missing.
