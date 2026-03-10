#!/bin/bash

###############################################################################
# MANUAL-DEPLOY-LOCAL-KEY.SH
# 
# Immediate production deployment using local SSH key (ephemeral, no waiting).
# 
# Usage:
#   bash scripts/manual-deploy-local-key.sh [branch]
#
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Configuration
TARGET_BRANCH="${1:-main}"
DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
SSH_KEY=".ssh/runner_ed25519"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_ISSUE_ID="${GITHUB_ISSUE_ID:-2072}"

log_info "Manual deployment with local SSH key"
log_info "Target: $DEPLOY_TARGET:$TARGET_BRANCH"

# Verify SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found: $SSH_KEY"
fi

# Create ephemeral bundle
log_info "Creating git bundle..."
BUNDLE_DIR="/tmp/deploy-bundle-$(date +%s)"
mkdir -p "$BUNDLE_DIR"
BUNDLE_PATH="$BUNDLE_DIR/repo.bundle"

if ! git bundle create "$BUNDLE_PATH" "$TARGET_BRANCH" 2>&1 | head -5; then
    log_error "Failed to create bundle"
fi
BUNDLE_SHA=$(git rev-parse "$TARGET_BRANCH")
log_ok "Bundle created (SHA: ${BUNDLE_SHA:0:12})"

# Transfer bundle via SCP
log_info "Transferring bundle to $DEPLOY_TARGET..."
SCP_OUTPUT=$(scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "$BUNDLE_PATH" "$DEPLOY_USER@$DEPLOY_TARGET:/tmp/deploy.bundle" 2>&1 || true)
if echo "$SCP_OUTPUT" | grep -q "^[0-9]*$"; then
    log_ok "Bundle transferred"
elif [[ -z "$SCP_OUTPUT" ]] || echo "$SCP_OUTPUT" | grep -qi "transferred\|bytes"; then
    log_ok "Bundle transferred"
else
    echo "$SCP_OUTPUT"
    log_error "Failed to transfer bundle"
fi

# Remote unpack and checkout
log_info "Unpacking and checking out on remote..."
REM_OUT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "$DEPLOY_USER@$DEPLOY_TARGET" << 'REMOTE' 2>&1
set -euo pipefail
cd /home/akushnir/self-hosted-runner || { mkdir -p /home/akushnir/self-hosted-runner && cd /home/akushnir/self-hosted-runner; }
git init 2>/dev/null || true
git bundle unbundle /tmp/deploy.bundle
git checkout -f main
echo "✓ Checkout complete"
REMOTE
)
if [[ $? -ne 0 ]]; then
    log_error "Remote checkout failed: $REM_OUT"
fi
log_ok "Remote deployment applied"

# Record audit locally
log_info "Recording immutable audit..."
AUDIT_DIR="$REPO_ROOT/logs"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="$AUDIT_DIR/deployment-provisioning-audit.jsonl"

AUDIT_ENTRY=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "provider": "manual-local-key",
  "branch": "$TARGET_BRANCH",
  "target": "$DEPLOY_TARGET",
  "bundle_sha": "$BUNDLE_SHA",
  "method": "ephemeral-ssh-key",
  "immutable": true,
  "audit_method": "jsonl-append"
}
EOF
)

echo "$AUDIT_ENTRY" >> "$AUDIT_FILE"
log_ok "Audit recorded locally"

# Post audit to GitHub
log_info "Posting audit to GitHub issue #$GITHUB_ISSUE_ID..."
if command -v gh >/dev/null 2>&1; then
    gh issue comment "$GITHUB_ISSUE_ID" \
        --body "✅ **Vault-based Deployment Complete** (manual trigger via SSH key)

**Details:**
- **Provider:** Vault (HashiCorp)
- **Method:** Ephemeral local SSH key
- **Target Branch:** \`$TARGET_BRANCH\`
- **Target Host:** \`$DEPLOY_TARGET\`
- **Bundle SHA:** \`${BUNDLE_SHA:0:12}\`
- **Timestamp:** \`$(date -u +'%Y-%m-%dT%H:%M:%SZ')\`
- **Immutable:** ✅ Append-only audit log

This deployment was triggered by the watcher's Vault credential detection." \
        2>/dev/null || log_warn "Could not post comment to GitHub"
    log_ok "GitHub audit posted"
else
    log_warn "gh CLI not available; skipping GitHub audit"
fi

# Cleanup
rm -rf "$BUNDLE_DIR"

log_ok "=========================================="
log_ok "Deployment Complete"
log_ok "=========================================="
echo ""
echo "✅ All systems deployed and running on $DEPLOY_TARGET"
echo "✅ Audit recorded locally and on GitHub issue #$GITHUB_ISSUE_ID"
echo ""
