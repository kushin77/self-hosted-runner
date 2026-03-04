#!/usr/bin/env bash
set -euo pipefail

echo "Running provision flow smoke test"
cwd=$(pwd)
cd "$(dirname "$0")/.."

# start server on ephemeral port
PORT=$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()
PY
)
SIMULATE_OAUTH=1 PORT=$PORT node index.js &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT

sleep 0.5

echo "Hit /auth/github to get state"
REDIR=$(curl -sI -o /dev/null -w "%{redirect_url}" "http://localhost:$PORT/auth/github" || true)
if [ -z "$REDIR" ]; then
  REDIR=$(curl -s -D - "http://localhost:$PORT/auth/github" -o /dev/null | grep -i Location | awk '{print $2}' | tr -d '\r') || true
fi
STATE=$(echo "$REDIR" | sed -n 's/.*[&?]state=\([^&]*\).*/\1/p')

echo "Calling callback with code=test-code and state=$STATE"
RESP=$(curl -s "http://localhost:$PORT/auth/github/callback?code=test-code&state=$STATE")
echo "Callback response: $RESP"

TOKEN=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token'))")
echo "Using token: $TOKEN"

echo "Registering runner"
REG=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"access_token":"'"$TOKEN"'","runner_meta":{"type":"test"}}' "http://localhost:$PORT/register-runner")
echo "Register response: $REG"

if echo "$REG" | grep -q 'provisioned'; then
  echo "Provision flow PASSED"
  exit 0
else
  echo "Provision flow FAILED" >&2
  exit 2
fi
