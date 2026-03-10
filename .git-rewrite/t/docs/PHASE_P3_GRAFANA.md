# Phase P3.3: Grafana Dashboard for Provisioner-Worker

This document describes the initial Grafana dashboard required for Phase P3 observability. The JSON file `docs/GRAFANA_DASHBOARD_JOB_FLOW.json` can be imported into Grafana.

## Panels

1. **Jobs Processed** (counter)
2. **Job Success Rate** (derived percentage)
3. **Queue Depth** (gauge)
4. **p95 Job Latency** (histogram quantile)

## Usage

```bash
# export to Grafana
curl -X POST "http://grafana.example.com/api/dashboards/db" \
  -H "Content-Type: application/json" \
  -d @docs/GRAFANA_DASHBOARD_JOB_FLOW.json \
  -H "Authorization: Bearer $GRAFANA_API_KEY"
```

## Next Steps

- Add panels for Vault connectivity & token refresh
- Add templating variables (e.g., instance_id)
- Add alerts to dashboard
