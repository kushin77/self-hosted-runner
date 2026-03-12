#!/usr/bin/env bash
set -euo pipefail
# Admin enforcement helper — run with TOKEN env var set to a GitHub PAT with repo:admin scope
# Usage: TOKEN=ghp_xxx ./scripts/ops/admin_enforcement.sh

REPO="kushin77/self-hosted-runner"

if [ -z "${TOKEN-}" ]; then
  echo "ERROR: set TOKEN env to a GitHub PAT with repo:admin scope" >&2
  exit 2
fi

echo "Setting branch protection for 'main' to require Cloud Build status checks..."
gh api -X PUT \
  /repos/$REPO/branches/main/protection/required_status_checks \
  -F strict=true -F contexts[]=validate-policies-and-keda || true

echo "Configuring pull request review requirements (dismiss stale reviews)..."
gh api -X PUT \
  /repos/$REPO/branches/main/protection/required_pull_request_reviews \
  -f dismiss_stale_reviews=true -f require_code_owner_reviews=false -f required_approving_review_count=1 || true

echo "Enforcing admins on branch protection..."
gh api -X PUT \
  /repos/$REPO/branches/main/protection/enforce_admins -f enabled=true || true

echo "Blocking GitHub Actions and Releases (repo-level where supported)..."
# Disable Actions via repository settings (may require organization-level enforcement)
gh api -X PUT /repos/$REPO/actions/permissions -f enabled=false || true

# Block Releases by creating a repo marker file (admins should also disable Releases in UI)
gh api -X PUT /repos/$REPO/contents/.github/RELEASES_BLOCKED -f message='chore: block releases (policy)' -f content="$(printf 'Releases are blocked by policy and must be approved by admins.' | base64 -w0)" || true

echo "Done — verify in GitHub UI or with 'gh api' queries."
