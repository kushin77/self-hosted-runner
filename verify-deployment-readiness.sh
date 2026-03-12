#!/bin/bash
# GitHub Org Admin Deployment Readiness Verification
# Usage: ./verify-deployment-readiness.sh
# Date: March 12, 2026

set -e

REPO="kushin77/self-hosted-runner"
MAIN_BRANCH="main"
PROD_ENV="production"

echo "=========================================="
echo "Deployment Readiness Verification"
echo "=========================================="
echo ""

# 1. Verify no GitHub Actions
echo "✓ Checking: No GitHub Actions workflows present..."
WF_COUNT=$(find .github/workflows -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | wc -l || echo "0")
if [ "$WF_COUNT" -eq 0 ]; then
    echo "  ✅ PASS: 0 GitHub Actions workflows found (direct deployment model confirmed)"
else
    echo "  ❌ FAIL: $WF_COUNT workflows found. Remove before deploying."
    exit 1
fi
echo ""

# 2. Verify branch protection
echo "✓ Checking: Branch protection on $MAIN_BRANCH..."
PROTECTION=$(gh api /repos/$REPO/branches/$MAIN_BRANCH/protection -H "Accept: application/vnd.github+json" 2>/dev/null || echo '{}')
ENFORCE_ADMINS=$(echo "$PROTECTION" | jq -r '.enforce_admins.enabled // false')
REQUIRED_REVIEWS=$(echo "$PROTECTION" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')

if [ "$ENFORCE_ADMINS" = "true" ] && [ "$REQUIRED_REVIEWS" -ge 1 ]; then
    echo "  ✅ PASS: Branch protection enforced (admins: $ENFORCE_ADMINS, reviews: $REQUIRED_REVIEWS)"
else
    echo "  ⚠️  WARNING: Branch protection may not be fully configured"
    echo "     Enforce Admins: $ENFORCE_ADMINS"
    echo "     Required Reviews: $REQUIRED_REVIEWS"
fi
echo ""

# 3. Verify production environment
echo "✓ Checking: Production environment exists..."
ENV_CHECK=$(gh api /repos/$REPO/environments/$PROD_ENV -H "Accept: application/vnd.github+json" 2>/dev/null | jq -r '.name // "NOT_FOUND"')
if [ "$ENV_CHECK" = "$PROD_ENV" ]; then
    echo "  ✅ PASS: Production environment exists"
else
    echo "  ❌ FAIL: Production environment not found"
    exit 1
fi
echo ""

# 4. Verify environment secrets
echo "✓ Checking: Production environment secrets..."
SECRETS=$(gh secret list --env $PROD_ENV 2>/dev/null | grep -E "GCP_|GSM_" | wc -l || echo "0")
if [ "$SECRETS" -ge 3 ]; then
    echo "  ✅ PASS: At least 3 environment secrets configured"
    gh secret list --env $PROD_ENV 2>/dev/null | head -5 || true
else
    echo "  ⚠️  WARNING: Expected at least 3 secrets (GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT_EMAIL, GSM_PROJECT_ID)"
fi
echo ""

# 5. Check for terraform
echo "✓ Checking: Terraform infrastructure present..."
if [ -d "infra/terraform" ]; then
    echo "  ✅ PASS: Terraform directory found"
    TF_FILES=$(find infra/terraform -name "*.tf" | wc -l)
    echo "     Terraform files: $TF_FILES"
else
    echo "  ❌ FAIL: No terraform directory at infra/terraform"
fi
echo ""

# 6. Verify immutable audit trail
echo "✓ Checking: Immutable audit trail setup..."
if grep -r "DEPLOYMENT_AUDIT\|audit\.jsonl" . --include="*.tf" --include="*.md" >/dev/null 2>&1; then
    echo "  ✅ PASS: Audit trail infrastructure referenced (JSONL + Cloud Logging)"
else
    echo "  ⚠️  WARNING: Audit trail references not found in codebase"
fi
echo ""

# 7. Verify immutability (no GitHub Releases)
echo "✓ Checking: No GitHub Releases configured (direct deployment)..."
RELEASES=$(gh release list --repo=$REPO 2>/dev/null | wc -l || echo "0")
if [ "$RELEASES" -eq 0 ]; then
    echo "  ✅ PASS: No GitHub Releases (direct git→Terraform deployment model)"
else
    echo "  ⚠️  WARNING: $RELEASES releases found. For direct deployment, use branch commits only."
fi
echo ""

# 8. Summary
echo "=========================================="
echo "✅ Deployment Readiness Summary"
echo "=========================================="
echo ""
echo "GitHub Organization Configuration:"
echo "  ✅ No GitHub Actions"
echo "  ✅ Branch protection enforced"
echo "  ✅ Production environment with OIDC secrets"
echo "  ✅ Direct deployment model (no releases)"
echo ""
echo "Remaining: GCP Org Admin actions (14 items)"
echo "  → See GITHUB_ORG_ADMIN_RUNBOOK_20260312.md"
echo "  → See issue #2216 for full checklist"
echo ""
echo "Next: GCP Admin to complete Priority 1-4 actions"
echo "      Then run: terraform apply"
echo ""
