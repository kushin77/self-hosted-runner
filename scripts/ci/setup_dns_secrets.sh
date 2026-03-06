#!/bin/bash
# Script to retrieve AWS credentials from Vault and add to GitHub Secrets
# Usage: ./scripts/ci/setup_dns_secrets.sh <vault_role_id> <vault_secret_id> <route53_zone_id> <ssh_private_key_path>

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"

if [ $# -lt 4 ]; then
  echo "Usage: $0 <vault_role_id> <vault_secret_id> <route53_zone_id> <ssh_key_path>"
  echo ""
  echo "Arguments:"
  echo "  vault_role_id      - AppRole Role ID for Vault authentication"
  echo "  vault_secret_id    - AppRole Secret ID for Vault authentication"
  echo "  route53_zone_id    - Route53 Zone ID for internal.elevatediq.com (format: Z...)"
  echo "  ssh_key_path       - Path to SSH private key for Ansible (PEM format)"
  echo ""
  echo "Example:"
  echo "  $0 b85ba861-7c54-546b-2d51-628fe7e5cd3e <secret-id> Z1234567890ABC /path/to/id_rsa"
  exit 1
fi

ROLE_ID="$1"
SECRET_ID="$2"
ROUTE53_ZONE_ID="$3"
SSH_KEY_PATH="$4"

echo "=== DNS Automation Secrets Setup ==="
echo ""
echo "Authenticating to Vault at $VAULT_ADDR..."

# Authenticate to Vault
AUTH_RESPONSE=$(curl -sS -X POST \
  "${VAULT_ADDR}/v1/auth/approle/login" \
  -d "{\"role_id\": \"${ROLE_ID}\", \"secret_id\": \"${SECRET_ID}\"}")

CLIENT_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.auth.client_token // empty')
if [ -z "$CLIENT_TOKEN" ]; then
  echo "ERROR: Failed to authenticate to Vault. Check credentials."
  echo "Response: $AUTH_RESPONSE"
  exit 1
fi

echo "✓ Vault authentication successful"
echo ""
echo "Retrieving AWS credentials from Vault..."

# Get AWS credentials from Vault
AWS_CREDS=$(curl -sS -H "X-Vault-Token: ${CLIENT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/aws" 2>/dev/null || echo "{}")

AWS_ACCESS_KEY=$(echo "$AWS_CREDS" | jq -r '.data.data.access_key_id // empty')
AWS_SECRET_KEY=$(echo "$AWS_CREDS" | jq -r '.data.data.secret_access_key // empty')

if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_KEY" ]; then
  echo "WARNING: AWS credentials not found in Vault at secret/data/aws"
  echo "You can manually add them using: gh secret set"
  AWS_ACCESS_KEY=""
  AWS_SECRET_KEY=""
fi

# Validate SSH key
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "ERROR: SSH key not found at $SSH_KEY_PATH"
  exit 1
fi

SSH_KEY=$(cat "$SSH_KEY_PATH")
if [ -z "$SSH_KEY" ]; then
  echo "ERROR: SSH key is empty"
  exit 1
fi

echo ""
echo "=== Adding secrets to GitHub repository ==="
echo ""

# Add secrets to GitHub
if [ -n "$AWS_ACCESS_KEY" ] && [ -n "$AWS_SECRET_KEY" ]; then
  echo "Adding AWS_ACCESS_KEY_ID..."
  gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY"
  
  echo "Adding AWS_SECRET_ACCESS_KEY..."
  gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_KEY"
fi

echo "Adding ROUTE53_ZONE_ID..."
gh secret set ROUTE53_ZONE_ID --body "$ROUTE53_ZONE_ID"

echo "Adding ANSIBLE_PRIVATE_KEY..."
gh secret set ANSIBLE_PRIVATE_KEY --body "$SSH_KEY"

echo ""
echo "✓ All secrets added successfully!"
echo ""
echo "Next steps:"
echo "1. The auto-apply workflow will detect secrets within 5 minutes"
echo "2. Monitor at: https://github.com/$GITHUB_REPO/actions/workflows/terraform-dns-auto-apply.yml"
echo "3. Once Terraform succeeds, DNS will be created and Ansible will run automatically"
