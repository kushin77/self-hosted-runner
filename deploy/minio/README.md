# MinIO Helm chart (hardened scaffold)

This chart is a scaffold for deploying MinIO as an S3-compatible object store. It includes a StatefulSet with PVC templates, a Service, and optional ServiceMonitor for Prometheus.

Production guidance:
- Use the official MinIO operator or a hardened chart for large-scale deployments.
- Provide credentials via Kubernetes secrets or a Vault injector and enable auto-unseal/keys for production.
- Configure TLS via `tls.secretName` and set `tls.enabled=true`.

This PR provides a starting point; follow-ups will add Prometheus exporters, more replicas, cross-region replication, and CI smoke tests.
