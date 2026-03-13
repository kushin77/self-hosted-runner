#!/usr/bin/env bash
# Configure GitHub branch protection for main to require Cloud Build checks and CODEOWNERS approvals.
# Requires GH CLI authentication with repo admin privileges.
set -euo pipefail
OWNER=${OWNER:-kushin77}
REPO=${REPO:-self-hosted-runner}
BRANCH=${BRANCH:-main}
# Require status checks and CODEOWNERS approvals
gh api --method PUT "/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" -f required_status_checks='{"strict":true,"contexts":["policy-check-trigger","direct-deploy-trigger"]}' -f enforce_admins=true -f required_pull_request_reviews='{"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"required_approving_review_count":1}'
