#!/usr/bin/env bash
# Integration test for vault-shim metrics endpoint (Phase P3.5)
# Requirements: node installed, curl

set -euo pipefail

BASE="http://localhost:4200"
MET_PORT=$((9200 + RANDOM % 100))
METRICS="http://localhost:$MET_PORT"

cd "$(dirname "$0")" || exit 1

echo "Starting vault-shim service with metrics in background (METRICS_PORT=$MET_PORT)..."
METRICS_PORT=$MET_PORT node ../index.cjs &
PID=$!
trap "kill $PID" EXIT
sleep 1

# hit health and secret endpoints
curl -sf "$BASE/health" > /dev/null
curl -sf -X POST "$BASE/secret" -H 'Content-Type: application/json' -d '{"key":"foo"}' > /dev/null

# check metrics
if curl -sf "$METRICS/metrics" | grep -q "vault_shim_requests_total"; then
  echo "vault-shim metrics endpoint responding"
else
  echo "metrics missing"; kill $PID; exit 1
fi

before=$(curl -sf "$METRICS/metrics" | grep '^vault_shim_requests_total ' | awk '{print $2}')
curl -sf "$BASE/health" > /dev/null
sleep 0.2
after=$(curl -sf "$METRICS/metrics" | grep '^vault_shim_requests_total ' | awk '{print $2}')
if [ "$after" -gt "$before" ]; then
  echo "vault-shim counter incremented"
else
  echo "counter did not increment"; kill $PID; exit 1
fi

kill $PID

echo "vault-shim metrics test completed successfully."