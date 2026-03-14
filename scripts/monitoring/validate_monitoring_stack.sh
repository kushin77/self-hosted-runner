#!/usr/bin/env bash
set -euo pipefail

PROM_FILE="monitoring/prometheus.yml"
RULES_FILE="monitoring/alert_rules/canonical_secrets_rules.yaml"
SLO_FILE="monitoring/slo/slo_rules.yaml"
K8S_PHASE1_FILE="kubernetes/phase1-deployment.yaml"

for file in "$PROM_FILE" "$RULES_FILE" "$SLO_FILE" "$K8S_PHASE1_FILE"; do
  if [ ! -f "$file" ]; then
    echo "Missing required file: $file" >&2
    exit 1
  fi
done

echo "[1/6] Enforcing no default credentials in Prometheus config"
if rg -n "guest|password:\s*'guest'|username:\s*'guest'" "$PROM_FILE" >/dev/null; then
  echo "Found forbidden default credentials in $PROM_FILE" >&2
  exit 1
fi

echo "[2/6] Validating Alertmanager target is configured"
if ! rg -n "targets:\s*\['alertmanager:9093'\]" "$PROM_FILE" >/dev/null; then
  echo "Alertmanager target is not configured in $PROM_FILE" >&2
  exit 1
fi

echo "[3/6] Enforcing production environment labels"
if rg -n "env:\s*'development'" "$PROM_FILE" >/dev/null; then
  echo "Found development labels in production Prometheus config" >&2
  exit 1
fi

echo "[4/6] Validating Kubernetes manifest structure"
if ! rg -n "^\s*containers:" "$K8S_PHASE1_FILE" >/dev/null; then
  echo "Missing containers key in $K8S_PHASE1_FILE" >&2
  exit 1
fi

if command -v promtool >/dev/null 2>&1; then
  echo "[5/6] Running promtool rule checks"
  promtool check rules "$RULES_FILE"
  promtool check rules "$SLO_FILE"
else
  echo "[5/6] promtool not installed; skipping rule syntax checks"
fi

if command -v kubectl >/dev/null 2>&1; then
  if kubectl version --request-timeout=3s >/dev/null 2>&1; then
    if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
      echo "[6/6] Running kubectl client dry-run"
      kubectl apply --dry-run=client --validate=false -f "$K8S_PHASE1_FILE" >/dev/null
    else
      echo "[6/6] ServiceMonitor CRD missing; skipping kubectl dry-run for monitoring.coreos.com resources"
    fi
  else
    echo "[6/6] Kubernetes API unreachable; skipping kubectl dry-run"
  fi
else
  echo "[6/6] kubectl not installed; skipping client dry-run"
fi

echo "Monitoring stack validation passed."
