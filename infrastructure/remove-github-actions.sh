#!/bin/bash

################################################################################
# Remove all GitHub Actions workflows
# Enforce direct deployment only (no GitHub Actions, no PR releases)
#
# This script:
# 1. Removes all .github/workflows/*.yml files
# 2. Creates git commit to remove workflows
# 3. Disables workflow execution on GitHub
# 4. Redirects to direct on-prem deployment
################################################################################

set -euo pipefail

PROJECT_DIR="${1:-.}"
GIT_BRANCH="${GIT_BRANCH:-main}"

cd "${PROJECT_DIR}"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║        Removing GitHub Actions Workflows                 ║"
echo "║        Policy: Direct Deployment Only                    ║"
echo "║        Target: 192.168.168.42 (On-Premises)             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# List workflows to be removed
echo "Workflows to remove:"
find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | while read -r workflow; do
    echo "  - ${workflow}"
done

echo ""
read -p "Continue with removal? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

# Remove workflow files
echo "Removing workflow files..."
rm -f .github/workflows/*.yml .github/workflows/*.yaml

# Remove .github directory if empty
if [[ -d .github/workflows ]] && [[ -z "$(ls -A .github/workflows)" ]]; then
    rmdir .github/workflows
    echo "✓ Removed empty .github/workflows directory"
fi

if [[ -d .github ]] && [[ -z "$(ls -A .github)" ]]; then
    rmdir .github
    echo "✓ Removed empty .github directory"
fi

# Create replacement documentation
mkdir -p .github-deprecated
cat > .github-deprecated/WORKFLOWS_REMOVED.md <<'EOF'
# GitHub Actions Workflows - Deprecated

**Status**: All GitHub Actions workflows have been removed.

## Reason for Removal

NexusShield infrastructure has been moved to direct on-premises deployment:

1. **No GitHub Actions**: Bypassed completely for security and automation
2. **Direct Deployment**: Automatic deployment from git to 192.168.168.42
3. **No PR Releases**: Release management via git tags only (not GitHub releases)
4. **Hands-Off Automation**: Fully automated with no manual intervention required

## New Deployment Process

All deployments are now direct:

```bash
# On development workstation (.31):
git push origin main

# Automatically triggers on .42:
→ Continuous deployment (no manual approval needed)
→ Immutable infrastructure (no local state)
→ Ephemeral containers (safe to restart)
→ Idempotent operations (safe to re-run)
```

## Migration Complete

The following workflows have been removed:
- CI/CD pipelines
- Pull request validators
- Deployment approval workflows
- Release creation workflows
- Status check workflows

All functionality is now handled by:
- `/infrastructure/on-prem-dedicated-host.sh` - Direct deployment
- `/usr/local/bin/nexus-deploy-direct.sh` - Service deployment
- `/usr/local/bin/nexus-auto-deploy.sh` - Continuous deployment loop

## For Questions

See `.github-deprecated/` for deprecated workflow documentation.
EOF

echo "✓ Created deprecation notice: .github-deprecated/WORKFLOWS_REMOVED.md"

# Commit removal
echo ""
echo "Committing workflow removal to git..."

git add -A .github-deprecated/
git rm -rf .github/workflows/ 2>/dev/null || true
git rm -rf .github/ 2>/dev/null || true

if ! git diff --cached --quiet; then
    git commit -m "chore: Remove all GitHub Actions workflows

Replace with direct on-premises deployment to 192.168.168.42

Summary:
- Removed all .github/workflows/ automation
- No GitHub Actions (security: direct deployment only)
- No PR releases (git tags + direct deployment)
- Continuous deployment via nexus-auto-deploy.service
- Immutable infrastructure (no local state on .42)
- Ephemeral containers (safe restarts)
- Idempotent operations (safe re-runs)

Deployment flow:
  git push → .42 auto-deploys → validation → live

References:
- See .github-deprecated/WORKFLOWS_REMOVED.md
- See infrastructure/on-prem-dedicated-host.sh
- See /usr/local/bin/nexus-deploy-direct.sh"

    echo "✓ Commit created"
else
    echo "ℹ No changes to commit (workflows may already be removed)"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ✅ GitHub Actions Removed                             ║"
echo "║   Deployment Type: DIRECT (192.168.168.42)              ║"
echo "║   Release Type: Git tags (no GitHub releases)            ║"
echo "║   Automation: Hands-off, fully automated                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. git push origin main  (to deploy)"
echo "  2. Watch deployment on .42:"
echo "     sudo systemctl status nexusshield-auto-deploy.service"
echo "  3. Check logs:"
echo "     sudo tail -f /var/log/nexusshield/auto-deploy.log"
