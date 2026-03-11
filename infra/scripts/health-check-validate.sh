#!/bin/bash
# Validate health endpoints for backend and frontend
set -e
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$INFRA_DIR/terraform"
ENVIRONMENT="${1:-dev}"
ENV_TFVARS="$TF_DIR/environments/${ENVIRONMENT}.tfvars"

# Load urls from terraform outputs if available
OUTPUTS_FILE="$TF_DIR/outputs-${ENVIRONMENT}.json"
if [[ -f "$OUTPUTS_FILE" ]]; then
  BACKEND_URL=$(jq -r '.cloud_run_outputs.value.backend_service_url' "$OUTPUTS_FILE")
  FRONTEND_URL=$(jq -r '.cloud_run_outputs.value.frontend_service_url' "$OUTPUTS_FILE")
fi

BACKEND_URL="${BACKEND_URL:-$BACKEND_URL}"
FRONTEND_URL="${FRONTEND_URL:-$FRONTEND_URL}"

if [[ -z "$BACKEND_URL" || -z "$FRONTEND_URL" ]]; then
  echo "Backend or frontend URL not set. Ensure terraform outputs are exported to $OUTPUTS_FILE"
  exit 1
fi

echo "Checking backend health: $BACKEND_URL/health"
if curl -sSf "$BACKEND_URL/health" -m 10 >/dev/null 2>&1; then
  echo "BACKEND_HEALTH_OK"
else
  echo "BACKEND_HEALTH_FAIL"
  exit 2
fi

echo "Checking backend status: $BACKEND_URL/api/v1/status"
if curl -sSf "$BACKEND_URL/api/v1/status" -m 10 >/dev/null 2>&1; then
  echo "BACKEND_STATUS_OK"
else
  echo "BACKEND_STATUS_FAIL"
  exit 3
fi

echo "Checking frontend: $FRONTEND_URL"
if curl -sSf "$FRONTEND_URL" -m 10 >/dev/null 2>&1; then
  echo "FRONTEND_OK"
else
  echo "FRONTEND_FAIL"
  exit 4
fi

echo "All health checks passed"
