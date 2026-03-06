# Observability scaffold

This chart is a lightweight scaffold combining Prometheus, Grafana, and Loki deployments to make integration and CI work simpler. For production use, use the upstream `kube-prometheus-stack`, `grafana` and `loki` charts, and configure TLS, persistence, and RBAC.

Follow-ups:
- Replace scaffold with operator/stack charts and add PVCs, RBAC, ingress/TLS
- Add dashboards, alerting rules, and Prometheus serviceMonitor resources for runners/agents
