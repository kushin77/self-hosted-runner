#!/usr/bin/env bash
set -euo pipefail

# Simple smoke-check script for the portal stack.
# Usage: ./smoke-check.sh [HOST] (default localhost)

HOST=${1:-localhost}

echo "Checking API at http://$HOST:5000/health"
if curl -fsS --max-time 5 "http://$HOST:5000/health" >/dev/null; then
  echo "API: OK"
else
  echo "API: FAILED" >&2
  exit 2
fi

echo "Checking frontend at http://$HOST:3000"
if curl -fsS --max-time 5 "http://$HOST:3000" >/dev/null; then
  echo "Frontend: OK"
else
  echo "Frontend: FAILED" >&2
  exit 3
fi

echo "Smoke checks passed against $HOST"
