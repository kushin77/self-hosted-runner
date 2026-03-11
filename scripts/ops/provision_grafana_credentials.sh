#!/usr/bin/env bash
set -euo pipefail

# Idempotent Grafana credentials provisioner for GSM
# Auto-creates grafana-url and grafana-api-key secrets if not present
# Can be run standalone or as part of deployment pipeline

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "$PROJECT" ]; then
  echo "ERROR: GCP project not set. Run 'gcloud config set project PROJECT_ID'" >&2
  exit 1
fi

# Use environment variables if provided, otherwise use defaults/placeholders
GRAFANA_URL="${GRAFANA_URL:-https://grafana.monitoring.internal}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-$(openssl rand -hex 32 2>/dev/null || echo 'temp-key-change-in-grafana')}"

echo "Provisioning Grafana credentials to GSM..."
echo "  Project: $PROJECT"
echo "  Grafana URL: $GRAFANA_URL"

# Check if secrets exist
if gcloud secrets describe grafana-url --project="$PROJECT" >/dev/null 2>&1; then
  echo "  grafana-url: already exists (skipping)"
else
  echo "  grafana-url: creating..."
  printf "%s" "$GRAFANA_URL" | gcloud secrets create grafana-url \
    --data-file=- \
    --project="$PROJECT" \
    --replication-policy="automatic" || true
fi

if gcloud secrets describe grafana-api-key --project="$PROJECT" >/dev/null 2>&1; then
  echo "  grafana-api-key: already exists (skipping)"
else
  echo "  grafana-api-key: creating..."
  printf "%s" "$GRAFANA_API_KEY" | gcloud secrets create grafana-api-key \
    --data-file=- \
    --project="$PROJECT" \
    --replication-policy="automatic" || true
fi

echo "Provisioning complete. Grafana credentials available in GSM."
echo ""
echo "To override defaults on next run, use environment variables:"
echo "  export GRAFANA_URL='https://grafana.example.com'"
echo "  export GRAFANA_API_KEY='glsa_...' (from Grafana UI)"
echo "  bash scripts/ops/provision_grafana_credentials.sh"
