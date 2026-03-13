#!/usr/bin/env bash
set -euo pipefail

echo "Cloud Build smoke: starting"

if command -v go >/dev/null 2>&1; then
  echo "Running Go unit tests as smoke check"
  go test ./... -v
  echo "Go tests completed"
else
  echo "Go not available in build; performing container build as smoke check"
  docker build -t nexus-smoke:latest .
  echo "Container build completed"
fi

echo "Cloud Build smoke: finished"
