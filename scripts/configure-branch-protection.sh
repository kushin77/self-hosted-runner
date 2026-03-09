#!/bin/bash
# 10X BRANCH PROTECTION & GITHUB SETTINGS CONFIGURATION
# Enforces immutability and mandate rebuild policies via GitHub API

set -euo pipefail

REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
BRANCH="main"

echo "🔒 Configuring GitHub branch protection rules for 10X enforcement..."

# Require PR reviews
echo "Setting: Require pull request reviews..."
gh api repos/$REPO_OWNER/$REPO_NAME/branches/$BRANCH/protection \
  --input=- << EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "manifest-validation",
      "enforcement-checks",
      "integration-tests",
      "security-scan"
    ]
  },
  "enforce_admins": true,
  "require_code_owner_reviews": true,
  "require_last_push_approval": true,
  "dismiss_stale_reviews": false,
  "restrict_dismissals": true,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

echo "✅ Branch protection configured"

# Create or update CODEOWNERS
echo ""
echo "Creating CODEOWNERS file for .github/actions..."
cat > CODEOWNERS << 'OWNERS'
# Require code owner review for action changes
.github/actions/*/        @kushin77/platform-architects
.github/workflows/10x-*   @kushin77/platform-architects
scripts/10x-*             @kushin77/platform-architects
docs/10X-*                @kushin77/platform-architects

# Immutable audit logs
.github/.immutable-audit.log  @kushin77/platform-architects
OWNERS

git add CODEOWNERS && echo "✅ CODEOWNERS configured"

# Configure git hooks
echo ""
echo "Configuring git hooks..."
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
echo "✅ Git hooks configured"

echo ""
echo "✅ GitHub enforcement configuration complete"
echo ""
echo "Manual steps (requires GitHub UI or additional permissions):"
echo "  1. Go to Repository Settings > Branches > Branch protection rules"
echo "  2. Enable 'Require signed commits'"
echo "  3. Enable 'Require conversation resolution before merging'"
echo "  4. Set status check for: manifest validation, enforcement, tests, security"
