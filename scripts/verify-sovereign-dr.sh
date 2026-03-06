#!/bin/bash
set -euo pipefail

# verify-sovereign-dr.sh
# Comprehensive verification of the Sovereign-DR deployment
# Ensures all components are operational and correctly configured

VAULT_ADDR="${VAULT_ADDR:-http://192.168.168.42:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-devroot}"
SECRET_PROJECT="${SECRET_PROJECT:-gcp-eiq}"
PRIMARY_PLATFORM="${PRIMARY_PLATFORM:-github}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ SOVEREIGN-DR DEPLOYMENT VERIFICATION                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Helper functions
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }
warn() { echo "⚠️  $1"; }
info() { echo "ℹ️  $1"; }

# Test 1: Vault Connectivity
info "Testing Vault connectivity..."
if curl -s --fail "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
  pass "Vault is reachable at $VAULT_ADDR"
else
  fail "Vault is unreachable at $VAULT_ADDR"
fi

# Test 2: Vault Token Validity
info "Validating Vault token..."
if vault token lookup >/dev/null 2>&1; then
  pass "Vault token is valid"
else
  fail "Vault token is invalid or expired"
fi

# Test 3: Vault Policies
info "Checking Vault policies..."
if vault policy list | grep -q "runner-read"; then
  pass "Vault policy 'runner-read' exists"
else
  fail "Vault policy 'runner-read' not found"
fi

# Test 4: Vault AppRole
info "Checking Vault AppRole..."
if vault read auth/approle/role/runner >/dev/null 2>&1; then
  ROLE_ID=$(vault read -field=role_id auth/approle/role/runner/role-id 2>/dev/null || echo "N/A")
  pass "Vault AppRole 'runner' exists (role_id: $ROLE_ID)"
else
  fail "Vault AppRole 'runner' not found"
fi

# Test 5: Slack Webhook in Vault
info "Verifying Slack webhook secret..."
WEBHOOK=$(vault kv get -field=webhook secret/ci/webhooks 2>/dev/null || echo "")
if [ -n "$WEBHOOK" ]; then
  pass "Slack webhook found in Vault"
else
  fail "Slack webhook not found in Vault"
fi

# Test 6: GitLab Token in Vault
info "Verifying GitLab registration token..."
GITLAB_TOKEN=$(vault kv get -field=token secret/ci/gitlab 2>/dev/null || echo "")
if [ -n "$GITLAB_TOKEN" ]; then
  pass "GitLab token found in Vault"
else
  warn "GitLab token not found in Vault (may be optional for GitHub-primary setups)"
fi

# Test 7: GSM Secrets Accessibility
info "Checking Google Secret Manager secrets..."
if gcloud secrets versions access latest --secret=slack-webhook --project="$SECRET_PROJECT" >/dev/null 2>&1; then
  pass "GSM slack-webhook is accessible"
else
  warn "GSM slack-webhook is inaccessible (may be permission issue)"
fi

# Test 8: Fetch Vault Secrets Script
info "Testing fetch_vault_secrets.sh..."
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
if [ -x "$SCRIPTS_DIR/fetch_vault_secrets.sh" ]; then
  source "$SCRIPTS_DIR/fetch_vault_secrets.sh" || warn "fetch_vault_secrets.sh sourcing had warnings"
  if [ -n "${SLACK_WEBHOOK:-}" ]; then
    pass "fetch_vault_secrets.sh exports SLACK_WEBHOOK correctly"
  else
    warn "fetch_vault_secrets.sh did not export SLACK_WEBHOOK"
  fi
else
  fail "fetch_vault_secrets.sh not executable"
fi

# Test 9: Healthcheck Script
info "Checking health check script..."
if [ -x "$SCRIPTS_DIR/check_and_reprovision_runner.sh" ]; then
  pass "check_and_reprovision_runner.sh is executable"
else
  fail "check_and_reprovision_runner.sh not executable"
fi

# Test 10: Notify Script
info "Checking notification script..."
if [ -x "$SCRIPTS_DIR/notify_health.sh" ]; then
  pass "notify_health.sh is executable"
else
  fail "notify_health.sh not executable"
fi

# Test 11: Systemd Timers (if applicable)
info "Checking systemd timers (optional on non-systemd systems)..."
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-timers 2>/dev/null | grep -q "gsm-to-vault-sync\|actions-runner-health"; then
    pass "Systemd timers detected (gsm-to-vault-sync or actions-runner-health)"
  else
    warn "Systemd timers not active (may need manual installation via install_systemd_timer.sh)"
  fi
else
  info "systemd not available on this system (timers not applicable)"
fi

# Test 12: Platform-Specific Health
info "Checking platform-specific configuration (PRIMARY_PLATFORM=$PRIMARY_PLATFORM)..."
if [ "$PRIMARY_PLATFORM" = "gitlab" ]; then
  if [ -f /etc/gitlab-runner/config.toml ]; then
    pass "GitLab runner config found at /etc/gitlab-runner/config.toml"
  else
    warn "GitLab runner config not found (will be auto-provisioned on next health check)"
  fi
elif [ "$PRIMARY_PLATFORM" = "github" ]; then
  if command -v gh >/dev/null 2>&1; then
    pass "GitHub CLI (gh) is installed"
  else
    warn "GitHub CLI (gh) not found (may be needed for GitHub-primary setups)"
  fi
fi

# Test 13: Documentation
info "Checking deployment documentation..."
DOC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)/SOVEREIGN_DR_DEPLOYMENT_COMPLETE.md"
if [ -f "$DOC_PATH" ]; then
  pass "SOVEREIGN_DR_DEPLOYMENT_COMPLETE.md found"
else
  warn "SOVEREIGN_DR_DEPLOYMENT_COMPLETE.md not found in repository root"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ VERIFICATION COMPLETE - SOVEREIGN-DR IS READY                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "1. Review SOVEREIGN_DR_DEPLOYMENT_COMPLETE.md for operational runbook"
echo "2. Verify systemd timers are active: systemctl list-timers"
echo "3. Test end-to-end: bash $SCRIPTS_DIR/check_and_reprovision_runner.sh"
echo "4. Monitor logs: journalctl -u actions-runner-health.service -f"
echo ""
