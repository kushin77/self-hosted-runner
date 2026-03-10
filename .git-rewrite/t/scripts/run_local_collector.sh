#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy/otel"

echo "Starting local OpenTelemetry Collector (docker-compose)..."
pushd "$DEPLOY_DIR" >/dev/null
docker compose up -d
echo "Collector started. To view logs run: docker compose logs -f" 
echo "You can run existing send_otlp.sh or other test scripts to exercise the collector."
popd >/dev/null
