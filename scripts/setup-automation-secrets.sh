#!/usr/bin/env bash
set -euo pipefail

# scripts/setup-automation-secrets.sh
# Purpose: Set up all required GitHub secrets for hands-off automation
# This script creates SSH keys, provides PAT generation instructions, and sets secrets in GitHub

REPO="${1:-kushin77/self-hosted-runner}"
SECRETS_DIR="/tmp/runner-secrets-$(date +%s)"

log_info() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [secrets-setup] $*"
}

log_error() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [secrets-setup] ERROR: $*" >&2
}

log_header() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  $*"
  echo "═══════════════════════════════════════════════════════════════"
}

cleanup() {
  log_info "Cleaning up temporary secrets directory"
  rm -rf "$SECRETS_DIR" 2>/dev/null || true
}

trap cleanup EXIT

main() {
  log_header "AUTOMATION SECRETS SETUP"
  log_info "Repository: $REPO"
  log_info "Secrets directory: $SECRETS_DIR"
  
  mkdir -p "$SECRETS_DIR"
  
  # ─────────────────────────────────────────────────────────────
  log_header "STEP 1: Generate SSH Keypair for Deployment"
  
  if ! command -v ssh-keygen >/dev/null; then
    log_error "ssh-keygen not found. Install openssh-client"
    exit 1
  fi
  
  log_info "Generating ED25519 SSH keypair..."
  ssh-keygen -t ed25519 \
    -C "runner-deploy-$(date -u +%Y-%m-%d)" \
    -f "$SECRETS_DIR/deploy_key" \
    -N "" \
    -q
  
  if [ -f "$SECRETS_DIR/deploy_key" ] && [ -f "$SECRETS_DIR/deploy_key.pub" ]; then
    log_info "✓ SSH keys generated successfully"
    
    PRIVATE_KEY=$(cat "$SECRETS_DIR/deploy_key")
    PUBLIC_KEY=$(cat "$SECRETS_DIR/deploy_key.pub")
    
    log_info "Public key fingerprint:"
    ssh-keygen -l -f "$SECRETS_DIR/deploy_key" 2>/dev/null || true
  else
    log_error "Failed to generate SSH keys"
    exit 1
  fi
  
  # ─────────────────────────────────────────────────────────────
  log_header "STEP 2: Set GitHub Secrets"
  
  if ! command -v gh >/dev/null; then
    log_error "gh CLI not found. Install GitHub CLI and authenticate with: gh auth login"
    exit 1
  fi
  
  # Verify authentication
  log_info "Verifying GitHub authentication..."
  if ! gh auth status -h github.com >/dev/null 2>&1; then
    log_error "Not authenticated with GitHub. Run: gh auth login"
    exit 1
  fi
  
  # Set DEPLOY_SSH_KEY
  log_info "Setting DEPLOY_SSH_KEY secret..."
  if echo "$PRIVATE_KEY" | gh secret set DEPLOY_SSH_KEY --repo "$REPO" 2>&1; then
    log_info "✓ DEPLOY_SSH_KEY set successfully"
  else
    log_error "Failed to set DEPLOY_SSH_KEY"
    exit 1
  fi
  
  # ─────────────────────────────────────────────────────────────
  log_header "STEP 3: Generate GitHub PAT for RUNNER_MGMT_TOKEN"
  
  cat << 'EOF'

⚠️  MANUAL STEP REQUIRED ⚠️

You must create a GitHub Personal Access Token (PAT) with the following scopes:

✓ RECOMMENDED: Fine-Grained Classic PAT
  1. Go to: https://github.com/settings/tokens/new
  2. Token name: "runner-management-automation-$(date -u +%Y-%m-%d)"
  3. Select scopes:
     - repo (full control of private repositories)
     - admin:repo_hook (full control of repository hooks)
     - admin:public_repo_hook (full control of public repo hooks)
     - admin:org_hook (for org-wide settings, if needed)
  4. Select expiration: 90 days (for rotation schedule)
  5. Click "Generate token"
  6. Copy the token (you won't see it again!)

✓ ALTERNATIVE: GitHub CLI (if you have repo admin access)
  gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "$YOUR_PAT"

After creating the token, run:
  gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "$YOUR_PAT_HERE"

EOF

  log_info "Waiting for token to be set..."
  log_info "**IMPORTANT**: Set RUNNER_MGMT_TOKEN before deploying automation"
  
  # ─────────────────────────────────────────────────────────────
  log_header "STEP 4: Public Key for SSH Access"
  
  cat << EOF

Add this public key to your runner hosts for SSH access:

---BEGIN SSH PUBLIC KEY---
$PUBLIC_KEY
---END SSH PUBLIC KEY---

Add to: ~/.ssh/authorized_keys on each runner host

Or use this one-liner on a runner:
  echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys

EOF

  # ─────────────────────────────────────────────────────────────
  log_header "STEP 5: Verify Secrets Are Set"
  
  log_info "Checking if secrets are configured in GitHub..."
  
  if gh secret list --repo "$REPO" 2>/dev/null | grep -q "DEPLOY_SSH_KEY"; then
    log_info "✓ DEPLOY_SSH_KEY is configured"
  else
    log_error "✗ DEPLOY_SSH_KEY is NOT configured"
  fi
  
  if gh secret list --repo "$REPO" 2>/dev/null | grep -q "RUNNER_MGMT_TOKEN"; then
    log_info "✓ RUNNER_MGMT_TOKEN is configured"
  else
    log_error "⚠️  RUNNER_MGMT_TOKEN is NOT configured (you need to set this manually)"
  fi
  
  # ─────────────────────────────────────────────────────────────
  log_header "SUMMARY"
  
  cat << EOF

✅ Setup Complete

1. DEPLOY_SSH_KEY: Set ✓
   - Private key stored securely in GitHub Secrets
   - Public key ready for runner hosts (see above)

2. RUNNER_MGMT_TOKEN: Requires Manual Setup
   - Generate PAT at: https://github.com/settings/tokens/new
   - Scopes needed: repo, admin:repo_hook, admin:org_hook
   - Set with: gh secret set RUNNER_MGMT_TOKEN --repo $REPO --body "\$YOUR_PAT"

3. Public Key for Manual Host Setup:
   - Copy the public key above
   - Add to ~/.ssh/authorized_keys on each runner host

Next Steps:
1. Create RUNNER_MGMT_TOKEN PAT via GitHub web UI
2. Set it with gh CLI: gh secret set RUNNER_MGMT_TOKEN --repo $REPO --body "\$PAT"
3. Verify both secrets: gh secret list --repo $REPO
4. Deploy automation: Merge PR #1013 to main
5. Monitor: Watch runner-self-heal.yml in Actions tab

For troubleshooting, see: AUTOMATION_RUNBOOK.md

EOF

  log_info "Setup complete. Secrets are ready for automation deployment."
  
  return 0
}

main "$@"
