#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# GOVERNANCE ENFORCEMENT SCANNER
# ============================================================================
# Detects governance violations in release creation patterns
# - GitHub Actions bot releases (forbidden)
# - PR-based releases (forbidden)
# - Direct main branch releases (allowed, validated)
#
# USAGE: bash tools/governance-scan.sh
# OUTPUT: VIOLATION: <violation-text> (one per line, or empty if compliant)
#
# ============================================================================

set +u
REPO_OWNER="${GITHUB_OWNER:-kushin77}"
REPO_NAME="${GITHUB_REPO:-self-hosted-runner}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
set -u

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "ERROR: GITHUB_TOKEN not set" >&2
  exit 1
fi

echo "Scanning releases for governance violations..."
echo "  Repository: $REPO_OWNER/$REPO_NAME"
echo "  Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo ""

# Fetch all releases from GitHub API (paginated)
VIOLATION_COUNT=0
PAGE=1
PER_PAGE=100

while true; do
  RELEASES=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases?per_page=$PER_PAGE&page=$PAGE" 2>/dev/null || echo "[]")

  # Check if empty page (pagination end)
  RELEASE_COUNT=$(echo "$RELEASES" | jq 'length' 2>/dev/null || echo 0)
  if [[ $RELEASE_COUNT -eq 0 ]]; then
    break
  fi

  # Scan each release for violations
  echo "$RELEASES" | jq -r '.[] | "\(.id)|\(.tag_name)|\(.author.login)|\(.body)"' | while IFS='|' read -r RELEASE_ID TAG_NAME AUTHOR BODY; do
    # Violation 1: GitHub Actions bot created release
    if [[ "$AUTHOR" == "github-actions[bot]" ]]; then
      echo "VIOLATION: GitHub Actions bot created release: $TAG_NAME (author: $AUTHOR, id: $RELEASE_ID)"
      ((VIOLATION_COUNT++))
      continue
    fi

    # Violation 2: PR-based release (body typically contains PR reference)
    if echo "$BODY" | grep -iq "pull request\|PR #\|merge.*pr\|from pull"; then
      echo "VIOLATION: PR-based release detected: $TAG_NAME (potential PR release, id: $RELEASE_ID)"
      ((VIOLATION_COUNT++))
      continue
    fi

    # Violation 3: Release created by known automation bot (not allowed)
    if echo "$AUTHOR" | grep -iq "dependabot\|renovate\|codecov"; then
      echo "VIOLATION: Automated bot released: $TAG_NAME (author: $AUTHOR, id: $RELEASE_ID)"
      ((VIOLATION_COUNT++))
      continue
    fi

    # Valid: Direct main branch release by human (allowed)
    # No output needed for compliant releases
  done

  # Move to next page
  ((PAGE++))
done

# Summary (informational only, not a violation)
echo ""
echo "Scan complete. Violations found: $VIOLATION_COUNT"

# Exit with success even if violations found (violations are reported via VIOLATION: prefix)
exit 0
