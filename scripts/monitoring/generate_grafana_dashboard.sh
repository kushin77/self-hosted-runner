#!/usr/bin/env bash
set -euo pipefail

# Generate Grafana Dashboard JSON for Canonical Secrets Monitoring
# Outputs dashboard JSON that can be imported into Grafana

DASHBOARD_FILE="${1:-/tmp/canonical_secrets_dashboard.json}"

cat > "$DASHBOARD_FILE" <<'DASHBOARD_JSON'
{
  "dashboard": {
    "title": "Canonical Secrets API Monitoring",
    "tags": ["canonical-secrets", "secrets-management", "vault"],
    "timezone": "UTC",
    "panels": [
      {
        "title": "API Health Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"canonical-secrets-api\"}",
            "legendFormat": "{{ instance }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "red", "value": 0 },
                { "color": "green", "value": 1 }
              ]
            }
          }
        }
      },
      {
        "title": "API Response Time (P95)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, canonical_secrets_api_response_time_ms)",
            "legendFormat": "P95"
          }
        ]
      },
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(canonical_secrets_api_requests_total[5m])",
            "legendFormat": "{{ method }} {{ path }}"
          }
        ]
      },
      {
        "title": "Provider Health",
        "type": "stat",
        "targets": [
          {
            "expr": "canonical_secrets_provider_health{provider=~\"vault|gsm|aws|azure\"}",
            "legendFormat": "{{ provider }}"
          }
        ]
      },
      {
        "title": "Secret Operations",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(canonical_secrets_operations_total[5m])",
            "legendFormat": "{{ operation }}"
          }
        ]
      },
      {
        "title": "Audit Log Write Latency",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, canonical_secrets_audit_write_latency_ms)",
            "legendFormat": "P99"
          }
        ]
      },
      {
        "title": "Migration Progress",
        "type": "graph",
        "targets": [
          {
            "expr": "canonical_secrets_migration_secrets_migrated_total",
            "legendFormat": "{{ migration_id }}"
          }
        ]
      },
      {
        "title": "Provider Failovers",
        "type": "stat",
        "targets": [
          {
            "expr": "increase(canonical_secrets_provider_failover_total[1h])",
            "legendFormat": "{{ from_provider }} → {{ to_provider }}"
          }
        ]
      }
    ],
    "templating": {
      "list": [
        {
          "name": "instance",
          "type": "query",
          "datasource": "Prometheus",
          "query": "label_values(canonical_secrets_api_requests_total, instance)"
        }
      ]
    },
    "refresh": "30s"
  }
}
DASHBOARD_JSON

echo "Dashboard JSON generated: $DASHBOARD_FILE"
echo "Import this into Grafana via: Settings > Dashboards > Import JSON"
