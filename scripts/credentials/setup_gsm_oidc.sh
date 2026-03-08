#!/bin/bash
# setup_gsm_oidc.sh - Configure OIDC for GSM access
# Stub implementation for local development

set -euo pipefail

echo "Configuring OIDC for GSM access..."

# Check if GCP credentials are available
if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
    echo "⚠️  WARNING: GOOGLE_APPLICATION_CREDENTIALS not set"
    echo "    Skipping GSM OIDC setup - assuming local development"
    exit 0
fi

echo "✅ GSM OIDC setup validation complete (stub mode)"
exit 0
