#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}

# Read token from Secret Manager
TOKEN=$(gcloud secrets versions access latest --secret=uptime-check-token --project="$PROJECT")
 # Backend health check
 gcloud monitoring uptime create "nexus-backend-health" \
   --project="$PROJECT" \
   --resource-type=uptime-url \
   --resource-labels=host=nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app \
   --path="/health" \
   --request-method=get \
   --headers="Authorization=Bearer $TOKEN" \
   --protocol=https \
   --period=5 \
   --timeout=10 || true

 # Backend status check
 gcloud monitoring uptime create "nexus-backend-status" \
   --project="$PROJECT" \
   --resource-type=uptime-url \
   --resource-labels=host=nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app \
   --path="/api/v1/status" \
   --request-method=get \
   --headers="Authorization=Bearer $TOKEN" \
   --protocol=https \
   --period=5 \
   --timeout=10 || true

 # Frontend check
 gcloud monitoring uptime create "nexus-frontend" \
   --project="$PROJECT" \
   --resource-type=uptime-url \
   --resource-labels=host=nexus-shield-portal-frontend-2tqp6t4txq-uc.a.run.app \
   --path="/" \
   --request-method=get \
   --headers="Authorization=Bearer $TOKEN" \
   --protocol=https \
   --period=5 \
   --timeout=10 || true

echo "Uptime checks created (or already exist)."