#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="logs/epic6-smoke"
mkdir -p "$LOG_DIR"
OUT="$LOG_DIR/smoke-$(date -u +%FT%TZ).log"

echo "$(date -u +%FT%TZ) EPIC-6 smoke tests START" >> "$OUT"

run_step(){
  local name="$1"; shift
  echo "--- $name ---" >> "$OUT"
  if "$@" >> "$OUT" 2>&1; then
    echo "$(date -u +%FT%TZ) $name: OK" >> "$OUT"
  else
    echo "$(date -u +%FT%TZ) $name: FAIL" >> "$OUT"
  fi
}

# AWS
echo "Checking AWS credentials..." >> "$OUT"
if source scripts/aws/aws-credentials.sh >> "$OUT" 2>&1; then
  run_step "AWS sts get-caller-identity" aws sts get-caller-identity --output json
else
  echo "AWS credentials fetch failed" >> "$OUT"
fi

# GCP
echo "Checking GCP credentials..." >> "$OUT"
if source scripts/gcp/gcp-credentials.sh >> "$OUT" 2>&1; then
  run_step "GCP print-access-token" gcloud auth print-access-token --project=nexusshield-prod --quiet
else
  echo "GCP credentials fetch failed" >> "$OUT"
fi

# Azure
echo "Checking Azure credentials..." >> "$OUT"
if source scripts/azure-credentials.sh >> "$OUT" 2>&1; then
  run_step "Azure SP login and account show" az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" --output none && az account show --query '{name:name, subscriptionId:id}' -o json
else
  echo "Azure credentials fetch failed" >> "$OUT"
fi

echo "$(date -u +%FT%TZ) EPIC-6 smoke tests END" >> "$OUT"
echo "Logs: $OUT"
