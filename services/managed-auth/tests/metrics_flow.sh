#!/usr/bin/env bash
# Integration test for managed-auth metrics endpoint (Phase P3.5)
# Requirements: node installed, curl

set -euo pipefail

BASE="http://localhost:4000"
METRICS="http://localhost:9091"

cd "$(dirname "$0")" || exit 1

echo "Starting managed-auth service with metrics in background..."
node ../index.js &
PID=$!
trap "kill $PID" EXIT
sleep 1

# hit a couple of endpoints to generate metrics
curl -sf "$BASE/health" > /dev/null
curl -sf "$BASE/oauth/callback?code=foo" || true

# verify metrics endpoint returns expected counters
if curl -sf "$METRICS/metrics" | grep -q "managed_auth_requests_total"; then
  echo "metrics endpoint responding"
else
  echo "metrics missing"; kill $PID; exit 1
fi

# confirm counters increment after another request
before=$(curl -sf "$METRICS/metrics" | grep managed_auth_requests_total | awk '{print $2}')
curl -sf "$BASE/health" > /dev/null
sleep 0.2
after=$(curl -sf "$METRICS/metrics" | grep managed_auth_requests_total | awk '{print $2}')
if [ "$after" -gt "$before" ]; then
  echo "request counter incremented"
else
  echo "counter did not increment"; kill $PID; exit 1
fi

kill $PID

echo "managed-auth metrics test completed successfully."