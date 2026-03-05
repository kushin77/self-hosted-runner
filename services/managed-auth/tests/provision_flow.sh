#!/usr/bin/env bash
# Simple integration test for managed-auth service (Issue #8)
# Requirements: node installed, curl

set -euo pipefail

BASE="http://localhost:4000"

# ensure working directory is script location
cd "$(dirname "$0")" || exit 1

echo "Starting managed-auth service in background..."
node ../index.js &
PID=$!
trap "kill $PID" EXIT
sleep 1

# health
curl -sf "$BASE/health" || { echo "healthcheck failed"; exit 1; }
echo "health OK"

# simulate OAuth callback
token=$(curl -s "$BASE/oauth/callback?code=testcode" | grep -oE 'Your token: [0-9a-f]+' | awk '{print $3}')
if [ -z "$token" ]; then
  echo "failed to obtain token"; exit 1
fi

echo "obtained token: $token"

# provision runner
runner=$(curl -s -X POST "$BASE/runners" -H 'Content-Type: application/json' -d '{"name":"test-runner","token":"'$token'"}')

if echo "$runner" | grep -q 'test-runner'; then
  echo "runner provisioned: $runner"
else
  echo "runner creation failed"; exit 1
fi

echo "fetching runners list"
list=$(curl -s "$BASE/runners")
echo "$list"

# simulate usage record
curl -s -X POST "$BASE/usage" -H 'Content-Type: application/json' -d '{"runnerId":"r-1","seconds":120}'

billing=$(curl -s "$BASE/billing")
echo "billing: $billing"

kill $PID

echo "managed-auth tests completed successfully."
