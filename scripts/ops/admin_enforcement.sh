#!/usr/bin/env bash
set -euo pipefail

# Admin enforcement helper — run with TOKEN env var set to a GitHub PAT with repo:admin scope
# Usage: TOKEN=ghp_xxx ./scripts/ops/admin_enforcement.sh

REPO="kushin77/self-hosted-runner"

if [ -z "${TOKEN-}" ]; then
  echo "ERROR: set TOKEN env to a GitHub PAT with repo:admin scope" >&2
  echo "Usage: TOKEN=ghp_xxx $0" >&2
  exit 2
fi

echo "GitHub Repo Enforcement Helper"
echo "=============================="
echo "Repo: $REPO"
echo ""

echo "[1/5] Setting branch protection for 'main' to require Cloud Build status checks..."
gh api -X PUT \
  /repos/$REPO/branches/main/protection/required_status_checks \
  -F strict=true -F contexts[]=validate-policies-and-keda || echo "  ⚠ Note: may require org-level enforcement"

echo ""
echo "[2/5] Configuring pull request review requirements (dismiss stale reviews)..."
gh api -X PUT \
  /repos/$REPO/branches/main/protection/required_pull_request_reviews \
  -f dismiss_stale_reviews=true -f require_code_owner_reviews=false -f required_approving_review_count=1 || echo "  ⚠ Note: PR review config may need adjustment"

echo ""
echo "[3/5] Enforcing admins on branch protection..."
gh api -X PUT \
  /repos/$REPO/branches/main/protection/enforce_admins -f enabled=true || echo "  ⚠ Note: enforce_admins may already be set"

echo ""
echo "[4/5] Disabling GitHub Actions (repo-level)..."
gh api -X PUT /repos/$REPO/actions/permissions -f enabled=false || echo "  ⚠ Note: may require org-level enforcement"

echo ""
echo "[5/5] Adding releases block marker..."
gh api -X PUT /repos/$REPO/contents/.github/RELEASES_BLOCKED \
  -f message='chore: block releases (governance policy)' \
  -f content="$(printf 'Releases are blocked by governance policy.\nApproval required from repository admins.\n' | base64 -w0)" || echo "  ⚠ Note: releases block file may already exist"

echo ""
echo "================================"
echo "✓ Enforcement helper completed."
echo ""
echo "Next steps:"
echo "1. Verify branch protection in GitHub UI: Settings → Branches → main"
echo "2. Disable GitHub Actions in repo settings if not done org-wide"
echo "3. Review and block/restrict Releases in repo settings"
echo "4. Verify Cloud Build status checks are required on PRs to main"
