#!/usr/bin/env bash
set -euo pipefail

# scripts/setup-automation-secrets-direct.sh
# Purpose: Rapidly create and set all automation secrets
# Usage: GITHUB_REPO=kushin77/self-hosted-runner bash scripts/setup-automation-secrets-direct.sh

GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"
TEMP_KEYS_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TEMP_KEYS_DIR"
}

trap cleanup EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  AUTOMATION SECRETS - RAPID SETUP"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Verify gh CLI
if ! command -v gh >/dev/null; then
  echo "❌ ERROR: gh CLI not installed"
  echo "Install: https://cli.github.com OR apt-get install gh"
  exit 1
fi

# Verify authentication
echo "[1/4] Verifying GitHub authentication..."
if ! gh auth status 2>/dev/null | grep -q "Logged in"; then
  echo "❌ ERROR: Not authenticated with GitHub"
  echo "Run: gh auth login"
  exit 1
fi
echo "✓ Authenticated"
echo ""

# Generate SSH keys
echo "[2/4] Generating SSH keypair..."
ssh-keygen -t ed25519 \
  -C "runner-deploy-automation" \
  -f "$TEMP_KEYS_DIR/deploy_key" \
  -N "" \
  -q

PRIVATE_KEY=$(cat "$TEMP_KEYS_DIR/deploy_key")
PUBLIC_KEY=$(cat "$TEMP_KEYS_DIR/deploy_key.pub")

echo "✓ SSH keypair generated"
echo "  Fingerprint: $(ssh-keygen -l -f "$TEMP_KEYS_DIR/deploy_key" 2>/dev/null | awk '{print $2}')"
echo ""

# Set DEPLOY_SSH_KEY
echo "[3/4] Setting DEPLOY_SSH_KEY in GitHub..."
if echo "$PRIVATE_KEY" | gh secret set DEPLOY_SSH_KEY --repo "$GITHUB_REPO" 2>&1 | grep -q "✓" || [ $? -eq 0 ]; then
  echo "✓ DEPLOY_SSH_KEY set successfully"
else
  echo "⚠️  DEPLOY_SSH_KEY may not be set (check permissions)"
fi
echo ""

# List secrets
echo "[4/4] Verifying secrets..."
echo ""
SECRETS=$(gh secret list --repo "$GITHUB_REPO" 2>/dev/null | grep -E "DEPLOY_SSH_KEY|RUNNER_MGMT_TOKEN" || echo "")

if echo "$SECRETS" | grep -q "DEPLOY_SSH_KEY"; then
  echo "✓ DEPLOY_SSH_KEY: Configured"
else
  echo "❌ DEPLOY_SSH_KEY: NOT configured"
fi

if echo "$SECRETS" | grep -q "RUNNER_MGMT_TOKEN"; then
  echo "✓ RUNNER_MGMT_TOKEN: Configured"
else
  echo "⚠️  RUNNER_MGMT_TOKEN: NOT configured (requires manual setup)"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  PUBLIC KEY FOR RUNNER HOSTS"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "$PUBLIC_KEY"
echo ""
echo "Add to runner hosts:"
echo "  echo '$PUBLIC_KEY' >> ~/.ssh/authorized_keys"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "  NEXT STEP: CREATE RUNNER_MGMT_TOKEN"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Create a GitHub Personal Access Token:"
echo "  1. Go to: https://github.com/settings/tokens/new"
echo "  2. Token name: runner-management-automation"
echo "  3. Expiration: 90 days"
echo "  4. Scopes:"
echo "     ✓ repo (full control of private repositories)"
echo "     ✓ admin:repo_hook (full control of repository hooks)"
echo "     ✓ admin:org_hook (full control of organization hooks)"
echo ""
echo "Then set it with:"
echo "  gh secret set RUNNER_MGMT_TOKEN --repo $GITHUB_REPO --body \"\$YOUR_PAT_HERE\""
echo ""

echo "✅ DEPLOY_SSH_KEY is ready!"
echo "⏳ Awaiting RUNNER_MGMT_TOKEN..."
echo ""
