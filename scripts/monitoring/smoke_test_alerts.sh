#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Prometheus + Alertmanager integration.
# Usage:
#   PROM_URL=http://prometheus:9090 AM_URL=http://alertmanager:9093 ./scripts/monitoring/smoke_test_alerts.sh
# Optional: PUSHGATEWAY=http://pushgateway:9091 to push synthetic metrics

PROM_URL="${PROM_URL:-}"
AM_URL="${AM_URL:-}"
PUSHGATEWAY="${PUSHGATEWAY:-}"
AUTO_TRIAGE_GITHUB_ISSUES="${AUTO_TRIAGE_GITHUB_ISSUES:-false}"

if [ -z "$PROM_URL" ]; then
  echo "PROM_URL not set. Set PROM_URL to your Prometheus HTTP API endpoint." >&2
  exit 2
fi

echo "Checking Prometheus at $PROM_URL"
if ! curl -fsS "$PROM_URL/-/ready" >/dev/null 2>&1; then
  echo "Prometheus not reachable or not ready: $PROM_URL" >&2
  exit 3
fi

echo "Querying for SLO recording rule metric 'slo:availability:7d'"
res=$(curl -s --get "$PROM_URL/api/v1/query" --data-urlencode "query=slo:availability:7d")
echo "$res" | jq -r '.status' || true

if [ -n "$PUSHGATEWAY" ]; then
  echo "PUSHGATEWAY provided — pushing synthetic error metric to force alert conditions"
  cat <<EOF | curl --silent --data-binary @- $PUSHGATEWAY/metrics/job/smoke-test
# TYPE canonical_secrets_api_requests_total counter
canonical_secrets_api_requests_total{method="POST",path="/v1/test",status="500"} 100
canonical_secrets_api_requests_total{method="POST",path="/v1/test",status="200"} 1
EOF
  echo "Pushed synthetic metrics. Waiting 30s for Prometheus to scrape..."
  sleep 30
fi

echo "Checking for alerts in Prometheus (alerts endpoint)"
alerts=$(curl -s "$PROM_URL/api/v1/alerts")
echo "$alerts" | jq '.'

if [ -n "$AM_URL" ]; then
  echo "Querying Alertmanager for active alerts"
  curl -s "$AM_URL/api/v2/alerts" | jq '.' || true
fi

if [ "$AUTO_TRIAGE_GITHUB_ISSUES" = "true" ]; then
  echo "AUTO_TRIAGE_GITHUB_ISSUES enabled — triaging alerts into GitHub issues"
  PROM_URL="$PROM_URL" AM_URL="$AM_URL" \
    ./scripts/monitoring/triage_alerts_to_github_issues.sh
fi

echo "Smoke test complete. Review outputs above for active alerts or rule evaluations."
