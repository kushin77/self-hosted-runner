#!/usr/bin/env bash
set -euo pipefail

PORT=4000
export SIMULATE_OAUTH=1

# Start server in background
node index.js &
PID=$!
trap "kill $PID" EXIT

sleep 0.6

echo "Requesting /auth/github to get redirect and state"
HEADERS=$(curl -s -D - -o /dev/null "http://localhost:${PORT}/auth/github")
LOCATION=$(echo "$HEADERS" | grep -i '^Location:' | sed -E 's/Location: //I' | tr -d '\r')
echo "Redirect Location: $LOCATION"

STATE=$(echo "$LOCATION" | sed -n 's/.*[&?]state=\([^&]*\).*/\1/p')
if [ -z "$STATE" ]; then
  echo "State not found in redirect" >&2
  exit 2
fi

echo "Calling callback with simulated code and state"
RESPONSE=$(curl -s "http://localhost:${PORT}/auth/github/callback?code=testcode123&state=${STATE}")
echo "Response: $RESPONSE"

echo "$RESPONSE" | grep -q 'simulated-token-123'
echo "Integration test passed"

exit 0
