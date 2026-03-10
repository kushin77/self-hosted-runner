#!/usr/bin/env bash
set -euo pipefail

# Quick test harness for /api/v1/migrate
PORT=${PORT:-8080}
URL="http://127.0.0.1:${PORT}/api/v1/migrate"

echo "Testing dry-run migration request to $URL"
curl -sS -X POST "$URL" -H 'Content-Type: application/json' -d '{"source":"on-prem","destination":"gcp","mode":"dry-run"}' | jq .
