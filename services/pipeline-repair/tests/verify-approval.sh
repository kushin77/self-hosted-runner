#!/usr/bin/env bash
set -euo pipefail

PORT=8083
ADMIN_KEY=test-admin-key

# Resolve paths relative to this script so it works from any cwd
BASEDIR=$(cd "$(dirname "$0")/.." && pwd)

# Start server with high approval threshold so retry-strategy requires approval (0.9)
REPAIR_APPROVAL_THRESHOLD=0.9 ADMIN_API_KEY=$ADMIN_KEY PORT=$PORT node "$BASEDIR/lib/server.js" &
PID=$!
sleep 1

# Send sample event (retry-strategy score 0.8, below 0.9 threshold -> requires approval)
EVENT='{"id":"evt-approve","errorMessage":"Error: Connection timeout after 30s","attemptNumber":1, "forceApproval": true}'
RESPONSE=$(curl -s -X POST http://localhost:$PORT/analyze -H 'Content-Type: application/json' -d "$EVENT")

# Expect 202 pending approval
if echo "$RESPONSE" | grep -q 'PENDING_APPROVAL'; then
  echo "Pending approval as expected"
else
  echo "Unexpected response (expected pending approval): $RESPONSE"
  kill $PID || true
  exit 2
fi

# Approve the event
APP_RES=$(curl -s -X POST http://localhost:$PORT/approve -H "Content-Type: application/json" -H "X-API-Key: $ADMIN_KEY" -d '{"eventId":"evt-approve","approver":"ci-test"}')

echo "Approve response: $APP_RES"

# Re-run analyze (should return the recommendation now with approval attached)
RESPONSE2=$(curl -s -X POST http://localhost:$PORT/analyze -H 'Content-Type: application/json' -d "$EVENT")

kill $PID || true
wait $PID 2>/dev/null || true

if echo "$RESPONSE2" | grep -q 'REPAIR_IDENTIFIED' && echo "$RESPONSE2" | grep -q 'approval'; then
  echo "Approval flow PASS"
  exit 0
else
  echo "Approval flow FAIL: $RESPONSE2"
  exit 3
fi
