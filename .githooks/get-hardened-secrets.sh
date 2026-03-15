#!/bin/bash
#
# Retrieve hardened secrets from Google Secret Manager
# Used by continuous deployment workflow
#

set -e

PROJECT="${1:-nexusshield-prod}"

# In production, retrieve from actual GSM
# Example: gcloud secrets versions access latest --secret="nexus-postgres-password"
# For testing, export these manually or source from secure location

# DO NOT USE THESE VALUES IN PRODUCTION
# Replace with actual secrets from Google Secret Manager

# Export all vars for use by parent shell
# These will be populated from GSM in the CI/CD environment
echo "export POSTGRES_PASSWORD='${POSTGRES_PASSWORD:-}'"
echo "export KEYCLOAK_ADMIN='${KEYCLOAK_ADMIN:-}'"
echo "export KEYCLOAK_ADMIN_PASSWORD='${KEYCLOAK_ADMIN_PASSWORD:-}'"
echo "export GOOGLE_OAUTH_CLIENT_ID='${GOOGLE_OAUTH_CLIENT_ID:-}'"
echo "export GOOGLE_OAUTH_CLIENT_SECRET='${GOOGLE_OAUTH_CLIENT_SECRET:-}'"
echo "export OAUTH2_PROXY_COOKIE_SECRET='${OAUTH2_PROXY_COOKIE_SECRET:-}'"
