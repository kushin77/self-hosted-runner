#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}

# Read token from Secret Manager
TOKEN=$(gcloud secrets versions access latest --secret=uptime-check-token --project="$PROJECT")
 # Backend health check
 gcloud monitoring uptime create "nexus-backend-health" \
   --project="$PROJECT" \
   --host="nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app" \
   --path="/health" \
   --http-request-method=GET \
   --headers="Authorization=Bearer $TOKEN" \
   --period=300s \
   --timeout=10s || true

 # Backend status check
 gcloud monitoring uptime create "nexus-backend-status" \
   --project="$PROJECT" \
   --host="nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app" \
   --path="/api/v1/status" \
   --http-request-method=GET \
   --headers="Authorization=Bearer $TOKEN" \
   --period=300s \
   --timeout=10s || true

 # Frontend check
 gcloud monitoring uptime create "nexus-frontend" \
   --project="$PROJECT" \
   --host="nexus-shield-portal-frontend-2tqp6t4txq-uc.a.run.app" \
   --path="/" \
   --http-request-method=GET \
   --headers="Authorization=Bearer $TOKEN" \
   --period=300s \
   --timeout=10s || true

echo "Uptime checks created (or already exist)."