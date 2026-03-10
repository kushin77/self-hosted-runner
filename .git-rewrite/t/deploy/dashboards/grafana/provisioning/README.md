Grafana Provisioning (ConfigMap + Helm)
======================================

This directory documents how to provision dashboards into Grafana in Kubernetes.

Option A — create a ConfigMap with the dashboard JSON and let the Grafana chart pick it up:

1. Create a ConfigMap from the JSON file:

```bash
kubectl create configmap grafana-dashboard-otel --from-file=otel-basic-dashboard.json=./deploy/dashboards/grafana/otel-basic-dashboard.json -n monitoring
```

2. If using the Bitnami/Helm chart or the official Grafana Helm chart, configure dashboard provisioning or mount the ConfigMap as a volume. Example `values.yaml` snippet for the `grafana` Helm chart:

```yaml
dashboards:
  default:
    otel-basic-dashboard:
      json: |-
        # (paste JSON or reference a file during chart packaging)

sidecar:
  dashboards:
    enabled: true
    label: grafana_dashboard

```

Option B — use a small provisioning ConfigMap combined with `provisioning/dashboards` and `provisioning/datasources` per Grafana docs.

CI validation
-------------
Use the provided CI workflow `.github/workflows/ci-dashboard-validate.yml` to validate the dashboard imports cleanly into a fresh Grafana instance.
