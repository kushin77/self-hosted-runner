#!/usr/bin/env bash
set -euo pipefail

PORT=8082
NODE=$(command -v node || true)
if [ -z "$NODE" ]; then
  echo "node not found"
  exit 1
fi

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)

# Start server in background
PORT=$PORT node "$BASEDIR/lib/server.js" &
PID=$!
sleep 1

# Send sample event
RESPONSE=$(curl -s -X POST http://localhost:$PORT/analyze -H 'Content-Type: application/json' -d '{"id":"evt-test","errorMessage":"Error: Connection timeout after 30s","attemptNumber":1}')

kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

echo "$RESPONSE"

if echo "$RESPONSE" | grep -q 'REPAIR_IDENTIFIED'; then
  echo "Test PASS"
  exit 0
else
  echo "Test FAIL"
  exit 2
fi
