#!/usr/bin/env bash
# Setup script: Install pre-commit hook and validation tools
# Usage: ./scripts/setup-policy-enforcement.sh

set -euo pipefail

echo "Setting up policy enforcement..."

# Install pre-commit hook
if [ -d ".git" ]; then
    echo "Installing pre-commit hook..."
    ln -sf ../../scripts/.pre-commit-hook .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "  ✓ Pre-commit hook installed"
else
    echo "  ⚠ Not a git repository, skipping hook installation"
fi

# Make validation script executable
chmod +x scripts/validate-phase2-ready.sh
echo "  ✓ Phase 2 validation script ready"

# Create audit directory if needed
mkdir -p .audit-logs
echo "  ✓ Audit log directory ready"

echo ""
echo "Policy enforcement setup complete."
echo ""
echo "Available commands:"
echo "  ./scripts/validate-phase2-ready.sh    - Validate Phase 2 readiness"
echo "  git commit                            - Will run pre-commit hook automatically"
echo ""
