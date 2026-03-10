#!/bin/bash
# Validate that all required credentials are accessible
# Usage: ./validate-credentials.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE="${1:-}"
ERRORS=0
CHECKED=0

# Define required credentials by category
declare -A REQUIRED_CREDENTIALS=(
  # GCP
  ["gcp-service-account-key"]="GCP service account for deployments"
  ["gcp-project-id"]="GCP project ID"
  ["gcp-workload-identity"]="GCP Workload Identity provider URL"
  
  # AWS
  ["aws-access-key-id"]="AWS access key for cross-cloud operations"
  ["aws-secret-access-key"]="AWS secret key"
  ["aws-kms-key-id"]="AWS KMS key for encryption"
  
  # Database
  ["postgres-host"]="PostgreSQL database host"
  ["postgres-user"]="PostgreSQL username"
  ["postgres-password"]="PostgreSQL password"
  
  # API Keys
  ["github-token"]="GitHub personal access token"
  ["vault-token"]="HashiCorp Vault authentication token"
  ["docker-registry-creds"]="Docker registry credentials"
  
  # Terraform
  ["terraform-cloud-token"]="Terraform Cloud API token"
  ["terraform-state-bucket"]="Terraform state storage bucket"
)

# Optional credentials (not required but good to have)
declare -A OPTIONAL_CREDENTIALS=(
  ["slack-webhook"]="Slack webhook for notifications"
  ["datadog-api-key"]="Datadog monitoring API key"
  ["pagerduty-token"]="PagerDuty automation token"
)

echo "🔍 Credential Access Validation"
echo "=================================="
echo ""

# Check required credentials
echo "📋 REQUIRED CREDENTIALS:"
for CRED in "${!REQUIRED_CREDENTIALS[@]}"; do
  ((CHECKED++))
  DESC="${REQUIRED_CREDENTIALS[$CRED]}"
  
  if bash "$SCRIPT_DIR/load-credential.sh" "$CRED" >/dev/null 2>&1; then
    echo "  ✅ $CRED"
    [ -n "$VERBOSE" ] && echo "     → $DESC"
  else
    echo "  ❌ $CRED"
    [ -n "$VERBOSE" ] && echo "     → $DESC (NOT ACCESSIBLE)"
    ((ERRORS++))
  fi
done

echo ""
echo "📦 OPTIONAL CREDENTIALS:"
for CRED in "${!OPTIONAL_CREDENTIALS[@]}"; do
  ((CHECKED++))
  DESC="${OPTIONAL_CREDENTIALS[$CRED]}"
  
  if bash "$SCRIPT_DIR/load-credential.sh" "$CRED" >/dev/null 2>&1; then
    echo "  ✅ $CRED"
    [ -n "$VERBOSE" ] && echo "     → $DESC"
  else
    echo "  ⚠️  $CRED (optional, not found)"
    [ -n "$VERBOSE" ] && echo "     → $DESC (optional credential)"
  fi
done

echo ""
echo "=================================="
if [ $ERRORS -eq 0 ]; then
  echo "✅ All required credentials validated ($CHECKED total checked)"
  echo ""
  exit 0
else
  echo "❌ Credential validation FAILED"
  echo "   $ERRORS missing or inaccessible credential(s)"
  echo ""
  echo "📚 Fix credentials using:"
  echo "   1. Google Secret Manager: gcloud secrets create|update"
  echo "   2. HashiCorp Vault: vault kv put secret/<name>"
  echo "   3. AWS KMS + Env: export <NAME>_ENCRYPTED=..."
  echo "   4. Local keys: echo '...' > .credentials/<name>.key"
  echo ""
  exit 1
fi
