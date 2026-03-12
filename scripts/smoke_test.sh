#!/usr/bin/env bash
set -euo pipefail
# Minimal smoke tests: health and readiness checks
SERVICE_URL=${SERVICE_URL:-"https://$(gcloud run services describe $_SERVICE_NAME --region=$_REGION --platform=managed --format='value(status.url)')"}
echo "Running smoke tests against $SERVICE_URL"
# Health endpoint
if ! curl -fsS "$SERVICE_URL/ready" >/dev/null; then
  echo "Health check failed"
  exit 2
fi
# Simple API call
if ! curl -fsS "$SERVICE_URL/healthz" >/dev/null; then
  echo "API healthz failed"
  exit 2
fi

echo "Smoke tests passed"
exit 0
