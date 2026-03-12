#!/usr/bin/env bash
set -euo pipefail

# Idempotent helper to deploy Prometheus alerting rules and Alertmanager config.
# Behavior:
# - If running in k8s with kubectl configured and PrometheusOperator present, create/update a PrometheusRule CR.
# - Else, copy rule files to /etc/prometheus/rules (requires permissions) and restart Prometheus (best-effort).

RULE_FILE="monitoring/alert_rules/canonical_secrets_rules.yaml"
AM_FILE="monitoring/alertmanager/alertmanager.yml"

if command -v kubectl >/dev/null 2>&1; then
  echo "kubectl detected — applying PrometheusRule (PrometheusOperator required)."
  # Create a PrometheusRule manifest wrapper for PrometheusOperator
  cat > /tmp/canonical-secrets-promrule.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: canonical-secrets-rules
  labels:
    role: alert-rules
spec:
  groups:
$(sed 's/^/    /' "$RULE_FILE")
EOF
  kubectl apply -f /tmp/canonical-secrets-promrule.yaml || true
else
  echo "kubectl not available — attempting local deploy into /etc/prometheus/rules"
  sudo mkdir -p /etc/prometheus/rules
  sudo cp "$RULE_FILE" /etc/prometheus/rules/canonical_secrets_rules.yaml
  sudo cp "$AM_FILE" /etc/alertmanager/alertmanager.yml || true
  echo "Local deploy attempted — ensure Prometheus/Alertmanager are configured to load these files and restart services if necessary."
fi

echo "Deploy step complete (idempotent)."
