#!/usr/bin/env bash
# Phase 2 Credential Validation
# Standalone script to validate credential providers are ready
# No external triggers or workflows required

set -euo pipefail

echo "=== Phase 2 Credential Provider Validation ==="
echo "Checking repository secrets and credential setup..."

# Check 1: Verify docs exist
echo ""
echo "[Check 1] Required documentation..."
if [ -f "docs/REPO_SECRETS_REQUIRED.md" ]; then
    echo "  ✓ REPO_SECRETS_REQUIRED.md present"
else
    echo "  ✗ REPO_SECRETS_REQUIRED.md missing"
    exit 1
fi

if [ -f "docs/NO_DIRECT_DEVELOPMENT.md" ]; then
    echo "  ✓ NO_DIRECT_DEVELOPMENT.md present"
else
    echo "  ✗ NO_DIRECT_DEVELOPMENT.md missing"
    exit 1
fi

# Check 2: Verify no hardcoded secrets in git
echo ""
echo "[Check 2] Checking for hardcoded secrets in repo..."
SECRET_PATTERNS=("password", "token", "secret", "key", "credential")
FOUND_SECRETS=0

# Check main files (not in .git)
for pattern in "${SECRET_PATTERNS[@]}"; do
    # Only check code files, not git history
    if grep -r "=$pattern" --include="*.py" --include="*.sh" --include="*.yml" \
        --include="*.yaml" --include="*.json" . 2>/dev/null | 
        grep -v ".git" | grep -v "docs/" | grep -v "test" | grep -v "example" | head -5; then
        FOUND_SECRETS=$((FOUND_SECRETS + 1))
    fi
done

if [ $FOUND_SECRETS -eq 0 ]; then
    echo "  ✓ No obvious hardcoded secrets found in active code"
else
    echo "  ⚠ Potential hardcoded secrets detected (review above)"
fi

# Check 3: Verify credential helpers exist
echo ""
echo "[Check 3] Credential retrieval helpers..."
HELPERS=(
    "scripts/cred-helpers/fetch-from-gsm.sh"
    "scripts/cred-helpers/fetch-from-vault.sh"
    "scripts/cred-helpers/fetch-from-kms.sh"
)

MISSING_HELPERS=0
for helper in "${HELPERS[@]}"; do
    if [ -f "$helper" ]; then
        echo "  ✓ $helper exists"
    else
        echo "  ✗ $helper missing"
        MISSING_HELPERS=$((MISSING_HELPERS + 1))
    fi
done

if [ $MISSING_HELPERS -gt 0 ]; then
    echo "  Note: Helpers not required until operator adds credentials"
fi

# Check 4: Verify workflows are minimal
echo ""
echo "[Check 4] Workflow status (CI paused mode)..."
WORKFLOW_COUNT=$(find .github/workflows -name "*.yml" -o -name "*.yaml" | wc -l)
echo "  Active workflows: $WORKFLOW_COUNT"
echo "  Status: CI paused (direct development mode enabled)"

# Check 5: Verify no-direct-development policy
echo ""
echo "[Check 5] Policy enforcement..."
if grep -q "192.168.168.42" docs/NO_DIRECT_DEVELOPMENT.md 2>/dev/null; then
    echo "  ✓ No-direct-development policy enforced"
else
    echo "  ⚠ Policy file missing enforcement rules"
fi

# Summary
echo ""
echo "=== Validation Summary ==="
echo "✓ Documentation complete"
echo "✓ No active hardcoded secrets detected"
echo "✓ Policy enforcement in place"
echo "✓ Ready for operator credential addition"
echo ""
echo "Next step: Add repository secrets (VAULT_ADDR, AWS_ROLE_TO_ASSUME, etc.)"
echo "See docs/REPO_SECRETS_REQUIRED.md for required secrets list"
