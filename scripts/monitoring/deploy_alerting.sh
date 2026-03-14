#!/usr/bin/env bash
set -euo pipefail

# Idempotent helper to deploy Prometheus alerting rules and Alertmanager config.
# Behavior:
# - If running in k8s with kubectl configured and PrometheusOperator present, create/update a PrometheusRule CR.
# - Else, copy rule files to /etc/prometheus/rules (requires permissions) and restart Prometheus (best-effort).

RULE_FILE="monitoring/alert_rules/canonical_secrets_rules.yaml"
AM_FILE="monitoring/alertmanager/alertmanager.yml"

if [ ! -f "$RULE_FILE" ]; then
  echo "Missing rule file: $RULE_FILE" >&2
  exit 1
fi

if [ ! -f "$AM_FILE" ]; then
  echo "Missing Alertmanager file: $AM_FILE" >&2
  exit 1
fi

if command -v promtool >/dev/null 2>&1; then
  echo "Validating Prometheus rules with promtool"
  promtool check rules "$RULE_FILE"
fi

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
  kubectl apply -f /tmp/canonical-secrets-promrule.yaml
else
  echo "kubectl not available — attempting local deploy into /etc/prometheus/rules"
  sudo mkdir -p /etc/prometheus/rules
  sudo mkdir -p /etc/alertmanager
  sudo cp "$RULE_FILE" /etc/prometheus/rules/canonical_secrets_rules.yaml
  sudo cp "$AM_FILE" /etc/alertmanager/alertmanager.yml
  echo "Local deploy attempted — ensure Prometheus/Alertmanager are configured to load these files and restart services if necessary."
fi

echo "Deploy step complete (idempotent)."
