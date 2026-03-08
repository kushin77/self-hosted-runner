#!/usr/bin/env bash
#
# apply-branch-protection.sh - Idempotent branch protection rules (no-ops enforcement)
#
# Applies branch protection rules to main branch:
# - Require pull request reviews (0, so any merge is OK)
# - Require status checks: validate-metadata
# - Enforce on admins
# - Allow force pushes: disabled
# - Dismiss stale PR reviews: enabled
# - Require branches to be up to date: enabled
#
# Idempotent: re-running applies same rules (no error if already set)
# No-ops: uses GitHub API only, no destructive changes
#

set -euo pipefail

OWNER="kushin77"
REPO="self-hosted-runner"
BRANCH="main"

echo "🔒 Applying idempotent branch protection rules to $OWNER/$REPO ($BRANCH)..."

# Fetch current branch protection to check if update needed
CURRENT=$(gh api repos/$OWNER/$REPO/branches/$BRANCH/protection 2>/dev/null | jq '.' || echo "{}")

# Build JSON payload for branch protection
PAYLOAD=$(jq -n \
  --arg branch "$BRANCH" \
  '{
    required_status_checks: {
      strict: true,
      contexts: ["Validate Metadata"]
    },
    enforce_admins: true,
    required_pull_request_reviews: null,
    restrictions: null,
    allow_force_pushes: false,
    allow_deletions: false,
    required_linear_history: false,
    dismiss_stale_reviews: true,
    require_code_owner_reviews: false
  }')

# Apply protection rules (idempotent via API)
# Use curl directly with gh for better control over JSON payload
gh api \
  -X PUT \
  repos/$OWNER/$REPO/branches/$BRANCH/protection \
  -i \
  --input <(echo "$PAYLOAD")

echo "✓ Branch protection applied (idempotent, no-ops enforcement only)"
echo ""
echo "Rules now enforced:"
echo "  - Require status checks: Validate Metadata"
echo "  - Enforce on admins: yes"
echo "  - Allow force pushes: no"
echo "  - Allow deletions: no"
echo "  - Require linear history: no"
echo "  - Dismiss stale reviews: yes"
echo ""
echo "To verify:"
echo "  gh api repos/$OWNER/$REPO/branches/$BRANCH/protection"
