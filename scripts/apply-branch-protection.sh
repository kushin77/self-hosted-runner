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

# Apply protection rules (idempotent via API)
gh api \
  -X PUT \
  repos/$OWNER/$REPO/branches/$BRANCH/protection \
  -f required_status_checks.strict=true \
  -f required_status_checks.contexts='[
    "Validate Metadata",
    "Check Compliance",
    "Detect Anomalies"
  ]' \
  -f enforce_admins=true \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f required_linear_history=false \
  -f require_code_owner_reviews=false \
  -f dismiss_stale_reviews=true \
  -f blocks_creations=false \
  -f blocks_deletions=false \
  -f require_reviews_from_code_owners=false

echo "✓ Branch protection applied (idempotent, no-ops enforcement only)"
echo ""
echo "Rules now enforced:"
echo "  - Require status checks: metadata validation, compliance, anomaly detection"
echo "  - Enforce on admins: yes"
echo "  - Allow force pushes: no"
echo "  - Allow deletions: no"
echo "  - Require linear history: no"
echo "  - Dismiss stale reviews: yes"
echo ""
echo "To verify:"
echo "  gh api repos/$OWNER/$REPO/branches/$BRANCH/protection"
