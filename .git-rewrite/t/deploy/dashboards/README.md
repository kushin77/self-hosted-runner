Grafana Dashboards
==================

This folder contains starter Grafana dashboards for OTEL-based observability.

Importing
---------
1. In Grafana, go to Dashboards → Import.
2. Upload `deploy/dashboards/grafana/otel-basic-dashboard.json` or paste its JSON.
3. When prompted, select your Prometheus datasource (or set the `DS_PROMETHEUS` variable in the dashboard).

Notes & Best Practices
----------------------
- The queries are intentionally generic; depending on your OTEL Collector and SDK metrics names you may need to adapt metric names (examples use `otelcol_*` and `otel_*` fallbacks).
- Consider storing dashboards in a provisioning directory or as a ConfigMap and using Grafana provisioning for automated installs in Kubernetes.
- For multi-tenant or templated dashboards, replace literal datasource names with templated variables (example already uses `DS_PROMETHEUS`).
- Version dashboards under `deploy/dashboards/` and include a short changelog when updating panels.
