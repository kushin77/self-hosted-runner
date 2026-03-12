Smoke Test: Prometheus & Alertmanager

Quick usage:

```bash
# Check Prometheus health and recording rules
PROM_URL=http://prometheus:9090 ./scripts/monitoring/smoke_test_alerts.sh

# Push synthetic metrics (requires Pushgateway)
PROM_URL=http://prometheus:9090 PUSHGATEWAY=http://pushgateway:9091 ./scripts/monitoring/smoke_test_alerts.sh

# Also query Alertmanager
PROM_URL=http://prometheus:9090 AM_URL=http://alertmanager:9093 ./scripts/monitoring/smoke_test_alerts.sh
```

Notes:
- The script is idempotent and safe to run from CI or locally.
- If metrics are pushed, Prometheus must be configured to scrape the Pushgateway.
