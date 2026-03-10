#!/usr/bin/env bash
# Simple integration test for AI Oracle service (Issue #10)

set -euo pipefail

BASE="http://localhost:4101"

cd "$(dirname "$0")" || exit 1

node ../index.js &
PID=$!
trap "kill $PID" EXIT
sleep 1

curl -sf "$BASE/health" || { echo "health failed"; exit 1; }
echo "health ok"

# send a failing log
resp=$(curl -s -X POST "$BASE/analyze" -H 'Content-Type: application/json' -d '{"jobId":"job-123","logs":"build failed: ERROR at line 5"}')
echo "analysis response: $resp"

if echo "$resp" | grep -q 'rootCause'; then
  echo "analysis recorded"
else
  echo "analysis missing"; exit 1
fi

# retrieve results
results=$(curl -s "$BASE/results")
echo "results: $results"

kill $PID

echo "oracle tests passed"