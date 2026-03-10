#!/bin/bash
# sync-github-deployment.sh — Master orchestrator for GitHub sync (branch protection + issues)
# Requires: export auth_token="GITHUB_TOKEN"
# Usage: bash scripts/github/sync-github-deployment.sh [--all|--protection|--issues]

set -e

REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."

ACTION=${1:---all}

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║          GitHub Deployment Sync — Branch Protection + Issues           ║"
echo "║                     Repo: $REPO_OWNER/$REPO_NAME"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check token
if [ -z "$auth_token" ]; then
  echo "ERROR: auth_token not set."
  echo ""
  echo "To proceed, export your GitHub admin Personal Access Token:"
  echo "  export auth_token=\"YOUR_GITHUB_TOKEN\""
  echo ""
  echo "Token creation: https://github.com/settings/tokens"
  echo "Scopes needed: 'repo' (full control of private/public repos)"
  echo ""
  exit 1
fi

# Verify token
echo "[*] Verifying GitHub authentication..."
auth_response=$(curl -sS -H "Authorization: token $auth_token" https://api.github.com/user)
user_login=$(echo "$auth_response" | jq -r '.login // empty')

if [ -z "$user_login" ]; then
  echo "ERROR: Token authentication failed."
  echo "Response: $auth_response"
  exit 1
fi

echo "✅ Authenticated as: $user_login"
echo ""

case "$ACTION" in
  --all)
    echo "[*] Running full GitHub deployment sync..."
    echo ""
    bash "$SCRIPT_DIR/sync-branch-protection.sh"
    echo ""
    bash "$SCRIPT_DIR/sync-issues.sh" --create
    echo ""
    bash "$SCRIPT_DIR/sync-issues.sh" --verify
    ;;
  
  --protection)
    echo "[*] Syncing branch protection only..."
    echo ""
    bash "$SCRIPT_DIR/sync-branch-protection.sh"
    ;;
  
  --issues)
    echo "[*] Syncing GitHub issues only..."
    echo ""
    bash "$SCRIPT_DIR/sync-issues.sh" --create
    echo ""
    bash "$SCRIPT_DIR/sync-issues.sh" --verify
    ;;
  
  *)
    echo "Usage: $0 [--all|--protection|--issues]"
    echo ""
    echo "  --all         Apply branch protection + create/verify issues"
    echo "  --protection  Apply branch protection to main and production"
    echo "  --issues      Create/verify GitHub issues #2273-#2277"
    echo ""
    echo "Examples:"
    echo "  export auth_token=\"GITHUB_TOKEN\""
    echo "  bash $SCRIPT_DIR/sync-github-deployment.sh --all"
    echo "  bash $SCRIPT_DIR/sync-github-deployment.sh --protection"
    echo "  bash $SCRIPT_DIR/sync-github-deployment.sh --issues"
    exit 1
    ;;
esac

echo ""
echo "✅ GitHub deployment sync complete!"
echo ""
echo "Next steps:"
echo "  1. Verify branch protections: https://github.com/$REPO_OWNER/$REPO_NAME/settings/branches"
echo "  2. View GitHub issues: https://github.com/$REPO_OWNER/$REPO_NAME/issues"
echo "  3. Review logs in: $REPO_ROOT/logs/"
