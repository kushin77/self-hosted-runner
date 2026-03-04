#!/usr/bin/env bash
# Smoke integration test for services/managed-auth
set -euo pipefail

SIMULATE_OAUTH=1
# Pick an available ephemeral port using python3 if available, otherwise default
if command -v python3 >/dev/null 2>&1; then
  PORT=$(python3 - <<'PY'
import socket
s=socket.socket()
s.bind(('',0))
print(s.getsockname()[1])
s.close()
PY
)
else
  PORT=${PORT:-54321}
fi

echo "Starting Managed Auth server (smoke test) on port $PORT"
# Run the server from the current directory (index.js is colocated here)
PORT=$PORT SIMULATE_OAUTH=1 node index.js &
PID=$!

cleanup() {
  echo "Killing server PID $PID"
  kill $PID 2>/dev/null || true
}
trap cleanup EXIT

# wait for server to be up
for i in {1..15}; do
  if curl -s "http://localhost:$PORT/" | grep -q 'RunnerCloud Managed Auth Skeleton'; then
    echo "Server is up"
    break
  fi
  sleep 0.5
done

echo "Requesting /auth/github to get redirect state"
REDIR=$(curl -sI -o /dev/null -w "%{redirect_url}" "http://localhost:$PORT/auth/github" || true)
if [ -z "$REDIR" ]; then
  # follow headers to extract location
  REDIR=$(curl -s -D - "http://localhost:$PORT/auth/github" -o /dev/null | grep -i Location | awk '{print $2}' | tr -d '\r') || true
fi

echo "Redirect: $REDIR"
STATE=$(echo "$REDIR" | sed -n 's/.*[&?]state=\([^&]*\).*/\1/p')
if [ -z "$STATE" ]; then
  echo "Failed to extract state from redirect: $REDIR" >&2
  exit 2
fi

echo "Calling callback with simulated code"
RESP=$(curl -s "http://localhost:$PORT/auth/github/callback?code=test-code-123&state=$STATE")
echo "Response: $RESP"

if echo "$RESP" | grep -q 'simulated-token'; then
  echo "Smoke test PASSED: received simulated token"
  exit 0
else
  echo "Smoke test FAILED: did not find simulated token in response" >&2
  exit 3
fi
