#!/usr/bin/env bash
set -euo pipefail

# Idempotent deployment of Prometheus alert rules
PROM_NS=${PROM_NS:-monitoring}
ALERT_FILE="$(dirname "$0")/../../monitoring/alerts/nexusshield.rules.yaml"

if [ ! -f "$ALERT_FILE" ]; then
  echo "Alert file not found: $ALERT_FILE" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found" >&2
  exit 1
fi

echo "Applying Prometheus alert rules from $ALERT_FILE to namespace $PROM_NS"

# Wrap the Prometheus 'groups' file into a PrometheusRule CRD manifest and apply
tmpfile=$(mktemp /tmp/nexusshield-promrule.XXXX.yaml)
{
  echo "apiVersion: monitoring.coreos.com/v1"
  echo "kind: PrometheusRule"
  echo "metadata:" 
  echo "  name: nexusshield-rules"
  echo "  namespace: $PROM_NS"
  echo "spec:"
  sed 's/^/  /' "$ALERT_FILE"
} > "$tmpfile"

kubectl apply -f "$tmpfile" -n "$PROM_NS"
rc=$?
rm -f "$tmpfile"
if [ $rc -ne 0 ]; then
  echo "kubectl apply failed with code $rc" >&2
  exit $rc
fi
echo "Apply completed"
