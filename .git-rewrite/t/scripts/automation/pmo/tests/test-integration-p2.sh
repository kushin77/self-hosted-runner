#!/usr/bin/env bash
# Integration test covering P2 services together: managed-auth, livemirror-cache, ai-oracle

set -euo pipefail

# Start all services on different ports

cd "$(dirname "$0")/../../.." || exit 1

# managed-auth
cd services/managed-auth && node index.js &
MAUTH_PID=$!
sleep 1

# cache
cd ../livemirror-cache && node index.js &
CACHE_PID=$!
sleep 1

# ai oracle
cd ../ai-oracle && node index.js &
AI_PID=$!
sleep 1

# run basic end-to-end checks
curl -sf http://localhost:4000/health && echo "managed-auth ok"
curl -sf http://localhost:4100/health && echo "cache ok"
curl -sf http://localhost:4101/health && echo "ai oracle ok"

# create token
token=$(curl -s http://localhost:4000/oauth/callback?code=test | grep -oE 'Your token: [0-9a-f]+' | awk '{print $3}')
echo "token=$token"

# provision runner
curl -s -X POST http://localhost:4000/runners -H 'Content-Type: application/json' -d '{"token":"'$token'"}'

# warmup cache
curl -s -X POST http://localhost:4100/cache/warmup -H 'Content-Type: application/json' -d '{"strategy":"balanced"}'

# analyze logs
curl -s -X POST http://localhost:4101/analyze -H 'Content-Type: application/json' -d '{"jobId":"job-x","logs":"ERROR failure"}'

# shutdown
kill $MAUTH_PID $CACHE_PID $AI_PID

echo "P2 integration test completed"