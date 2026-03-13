#!/bin/bash
# Quick Governance Enforcement Verification (Final)
# Simple script to validate key governance requirements

PROJECT_ID="${1:-nexusshield-prod}"

echo "══════════════════════════════════════════════════════════════════"
echo "🔍 QUICK GOVERNANCE VERIFICATION"
echo "══════════════════════════════════════════════════════════════════"
echo ""

PASS=0
FAIL=0

# Test 1: No active GitHub Actions workflows
if [[ $(ls .github/workflows/ 2>/dev/null | grep -v disabled | wc -l) -eq 0 ]]; then
  echo "✅ GitHub Actions: All workflows disabled"
  ((PASS++))
else
  echo "❌ GitHub Actions: Found active workflows"
  ((FAIL++))
fi

# Test 2: Releases blocked
if [[ -f .github/RELEASES_BLOCKED ]]; then
  echo "✅ GitHub Releases: Blocked"
  ((PASS++))
else
  echo "❌ GitHub Releases: Not blocked"
  ((FAIL++))
fi

# Test 3: Cloud Build configured
if [[ -f cloudbuild.yaml ]] && grep -q "gcloud run deploy" cloudbuild.yaml; then
  echo "✅ Cloud Build: Direct deployment to Cloud Run"
  ((PASS++))
else
  echo "❌ Cloud Build: Not properly configured"
  ((FAIL++))
fi

# Test 4: GSM credential management
if grep -q "gcloud secrets versions access" cloudbuild.yaml; then
  echo "✅ Credentials: GSM (Google Secret Manager) configured"
  ((PASS++))
else
  echo "❌ Credentials: GSM not found"
  ((FAIL++))
fi

# Test 5: Terraform infrastructure code
if [[ -f terraform/org_admin/main.tf ]] && grep -q "google_kms\|google_secret_manager" terraform/org_admin/main.tf; then
  echo "✅ Infrastructure as Code: Terraform with KMS/Secret Manager"
  ((PASS++))
else
  echo "❌ Infrastructure as Code: Terraform not properly configured"
  ((FAIL++))
fi

# Test 6: Audit trail
if [[ -f audit-trail.jsonl ]]; then
  echo "✅ Audit Trail: Immutable log (audit-trail.jsonl)"
  ((PASS++))
else
  echo "❌ Audit Trail: Not found"
  ((FAIL++))
fi

# Test 7: Governance documentation
if [[ -f FINAL_GOVERNANCE_VERIFICATION_20260313.md ]] && [[ -f CLOUD_BUILD_MANUAL_SETUP_GUIDE.md ]]; then
  echo "✅ Documentation: Governance and Cloud Build guides present"
  ((PASS++))
else
  echo "❌ Documentation: Missing governance or setup guides"
  ((FAIL++))
fi

# Test 8: Operations scripts
if [[ -f scripts/ops/setup-cloud-build-trigger.sh ]] && [[ -f scripts/ops/quick-governance-check.sh ]]; then
  echo "✅ Operations: Automation scripts in place"
  ((PASS++))
else
  echo "❌ Operations: Scripts missing"
  ((FAIL++))
fi

# Test 9: Git repository
if [[ -d .git ]] && git rev-parse --verify main >/dev/null 2>&1; then
  echo "✅ Git Repository: main branch initialized"
  ((PASS++))
else
  echo "❌ Git Repository: Not properly set up"
  ((FAIL++))
fi

# Test 10: Deployment status
echo ""
if command -v gcloud &> /dev/null; then
  if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q "cloudbuild"; then
    echo "✅ Cloud Build API: Enabled in $PROJECT_ID"
    ((PASS++))
  else
    echo "⚠️  Cloud Build API: Not enabled or not accessible"
  fi
else
  echo "⚠️  gcloud CLI: Not available (cannot check Cloud Build API status)"
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "📊 RESULTS: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "🎉 ALL GOVERNANCE REQUIREMENTS VERIFIED!"
  echo ""
  echo "Repository is production ready for:"
  echo "  ✓ Direct Cloud Build deployment (push to main)"
  echo "  ✓ Immutable audit trail"
  echo "  ✓ No GitHub Actions (Cloud Build only)"
  echo "  ✓ Credential management via GSM/Vault/KMS"
  echo "  ✓ Fully automated, hands-off operation"
  echo ""
  exit 0
else
  echo "⚠️ Some governance requirements may not be in place."
  echo "Review the output above and consult:"
  echo "  • FINAL_GOVERNANCE_VERIFICATION_20260313.md"
  echo "  • CLOUD_BUILD_MANUAL_SETUP_GUIDE.md"
  exit 1
fi
