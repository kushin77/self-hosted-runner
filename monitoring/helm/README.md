Deploy Prometheus + Alertmanager via Helm

This folder contains example Helm values for `kube-prometheus-stack` (Prometheus Operator).

Usage (replace namespace and values as needed):

```bash
# Add repo if needed
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install or upgrade with our values
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/helm/prometheus-values.yaml
```

Notes:
- The `prometheus.prometheusSpec.ruleSelector` is configured to pick up rules labeled `role: alert-rules`.
- The `monitoring/servicemonitor/canonical-secrets-servicemonitor.yaml` manifest can be applied to the cluster to allow scraping the `canonical-secrets-api`.
- After deployment, apply the `monitoring/alert_rules/canonical_secrets_rules.yaml` as a `PrometheusRule` CR or mount it via ConfigMap according to your operator setup.
