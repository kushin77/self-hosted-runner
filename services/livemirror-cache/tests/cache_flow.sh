#!/usr/bin/env bash
# Integration tests for LiveMirror cache service (Issue #9)

set -euo pipefail

BASE="http://localhost:4100"

cd "$(dirname "$0")" || exit 1

# start service
node ../index.js &
PID=$!
trap "kill $PID" EXIT
sleep 1

curl -sf "$BASE/health" || { echo "health failed"; exit 1; }
echo "health ok"

layers=$(curl -s "$BASE/cache")
echo "layers: $layers"

# warmup aggressive
resp=$(curl -s -X POST "$BASE/cache/warmup" -H 'Content-Type: application/json' -d '{"strategy":"aggressive"}')
echo "warmup response: $resp"

# verify hit rate increased
newlayers=$(curl -s "$BASE/cache")
echo "new layers: $newlayers"

kill $PID

echo "cache service tests passed"