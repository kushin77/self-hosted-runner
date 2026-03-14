#!/bin/bash
set -euo pipefail

# Deploy Google OAuth services with credentials from GSM or environment variables
# Usage: bash scripts/deploy-oauth.sh [--setup-gsm]

SETUP_GSM="${1:-}"

echo "🔐 Google OAuth Deployment Script"
echo "=================================="
echo ""

# Check for --setup-gsm flag
if [[ "$SETUP_GSM" == "--setup-gsm" ]]; then
  echo "📋 Setting up Google OAuth secrets in GSM..."
  
  if [[ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" ]] || [[ -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "❌ Error: GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET must be set"
    echo ""
    echo "Follow GOOGLE_OAUTH_SETUP.md to obtain credentials:"
    echo "  1. Create Google Cloud project at https://console.cloud.google.com"
    echo "  2. Create OAuth 2.0 Web Application credentials"
    echo "  3. Set environment variables:"
    echo "     export GOOGLE_OAUTH_CLIENT_ID='YOUR_CLIENT_ID.apps.googleusercontent.com'"
    echo "     export GOOGLE_OAUTH_CLIENT_SECRET='YOUR_CLIENT_SECRET'"
    exit 1
  fi
  
  echo "  → Storing GOOGLE_OAUTH_CLIENT_ID in GSM..."
  echo -n "$GOOGLE_OAUTH_CLIENT_ID" | gcloud secrets create google-oauth-client-id --data-file=- 2>/dev/null || \
  echo -n "$GOOGLE_OAUTH_CLIENT_ID" | gcloud secrets versions add google-oauth-client-id --data-file=-
  
  echo "  → Storing GOOGLE_OAUTH_CLIENT_SECRET in GSM..."
  echo -n "$GOOGLE_OAUTH_CLIENT_SECRET" | gcloud secrets create google-oauth-client-secret --data-file=- 2>/dev/null || \
  echo -n "$GOOGLE_OAUTH_CLIENT_SECRET" | gcloud secrets versions add google-oauth-client-secret --data-file=-
  
  echo "✅ Google OAuth secrets saved to GSM"
  echo ""
fi

# Load credentials from GSM
echo "📥 Loading Google OAuth credentials from GSM..."
GOOGLE_OAUTH_CLIENT_ID=$(gcloud secrets versions access latest --secret="google-oauth-client-id" 2>/dev/null) || {
  echo "❌ Could not load google-oauth-client-id from GSM"
  echo "Run: bash scripts/deploy-oauth.sh --setup-gsm"
  exit 1
}

GOOGLE_OAUTH_CLIENT_SECRET=$(gcloud secrets versions access latest --secret="google-oauth-client-secret" 2>/dev/null) || {
  echo "❌ Could not load google-oauth-client-secret from GSM"
  echo "Run: bash scripts/deploy-oauth.sh --setup-gsm"
  exit 1
}

if [[ "$GOOGLE_OAUTH_CLIENT_ID" == *"REPLACE_WITH"* ]] || [[ "$GOOGLE_OAUTH_CLIENT_SECRET" == *"REPLACE_WITH"* ]]; then
  echo "❌ Google OAuth credentials are placeholders - please update them"
  echo "Run: bash GOOGLE_OAUTH_SETUP.md (Step 1-2 to get real credentials)"
  exit 1
fi

echo "✅ Credentials loaded successfully"
echo ""

# Deploy services with credentials
echo "🚀 Deploying OAuth2-Proxy and monitoring services..."
echo ""

export GOOGLE_OAUTH_CLIENT_ID
export GOOGLE_OAUTH_CLIENT_SECRET

docker-compose up -d oauth2-proxy monitoring-router grafana prometheus alertmanager node-exporter

echo ""
echo "✅ Services deployed successfully!"
echo ""
echo "📍 Access monitoring stack:"
echo "  → Grafana: http://192.168.168.42:3000"
echo "  → OAuth2-Proxy: http://192.168.168.42:4180"
echo "  → Prometheus: http://192.168.168.42:4180/prometheus"
echo "  → Alertmanager: http://192.168.168.42:4180/alertmanager"
echo ""
echo "🔐 All endpoints require Google OAuth authentication"
