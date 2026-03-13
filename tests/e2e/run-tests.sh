#!/bin/bash
# E2E Test Runner Script
# NOTE: This script runs tests against the mock server on the worker host (192.168.168.42)
# The mock server must be started on the worker first:
#   ssh akushnir@192.168.168.42
#   WORKER_HOST=192.168.168.42 node tests/e2e/mock-server.js &

set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default worker host - must be 192.168.168.42 per documentation
WORKER_HOST="${WORKER_HOST:-192.168.168.42}"
API_BASE_URL="http://${WORKER_HOST}:3000"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

# Check if WORKER_HOST is set (required for mock server)
if [ -z "$WORKER_HOST" ]; then
  echo "ERROR: WORKER_HOST environment variable must be set"
  echo "Usage: WORKER_HOST=192.168.168.42 bash run-tests.sh"
  exit 1
fi

# Validate worker host is not localhost (per documentation requirements)
if [ "$WORKER_HOST" = "localhost" ] || [ "$WORKER_HOST" = "127.0.0.1" ]; then
  echo "ERROR: localhost is not allowed. Use 192.168.168.42 (worker node)"
  echo "Per documentation: NEVER use localhost - always deploy to worker (192.168.168.42)"
  exit 1
fi

# Check if mock server is reachable
if ! curl -s "$API_BASE_URL/health" > /dev/null 2>&1; then
  echo "ERROR: Mock server not reachable at $API_BASE_URL"
  echo "Please start the mock server on the worker first:"
  echo "  ssh akushnir@192.168.168.42"
  echo "  WORKER_HOST=192.168.168.42 node tests/e2e/mock-server.js &"
  exit 1
fi

echo "Running E2E tests against $API_BASE_URL..."

# Run tests with correct base URL
export API_BASE_URL
if [ "$CI" = "true" ]; then
  npx playwright test --reporter=html --reporter=json --reporter=junit
else
  npx playwright test --reporter=list
fi

# Generate gap analysis report
echo "Generating gap analysis report..."
node generate-gap-analysis.ts

echo "✅ Tests complete"
