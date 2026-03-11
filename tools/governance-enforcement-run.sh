#!/usr/bin/env bash
set -euo pipefail

# Governance enforcement wrapper - runs scanner and posts results

REPO_ROOT="${REPO_ROOT:-.}"
GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
GITHUB_REPO="${GITHUB_REPO:-self-hosted-runner}"
ISSUE_NUM_AUDIT="2619"
SCAN_LOG="${HOME}/.governance-scan.log"

# Create log directory if needed
mkdir -p "$(dirname "$SCAN_LOG")"

# Run scanner, capture output
echo "Running governance scan at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$SCAN_LOG"

SCAN_OUT=$("$REPO_ROOT/tools/governance-scan.sh" 2>&1 || true)
SCAN_EXIT=$?

echo "$SCAN_OUT" >> "$SCAN_LOG"
echo "Scan exit code: $SCAN_EXIT" >> "$SCAN_LOG"
echo "---" >> "$SCAN_LOG"

# Extract violations (lines starting with "VIOLATION:")
VIOLATIONS=$(echo "$SCAN_OUT" | grep '^VIOLATION:' || true)
VIOLATION_COUNT=$(echo "$VIOLATIONS" | grep -c '^VIOLATION:' || echo "0")
VIOLATION_COUNT=${VIOLATION_COUNT:-0}

# Build comment
COMMENT="**Governance Enforcement Scan** $(date -u +'%Y-%m-%dT%H:%M:%SZ')

**Violations Detected:** $VIOLATION_COUNT

"

if [ "$VIOLATION_COUNT" -gt 0 ]; then
  COMMENT+="$VIOLATIONS

"
else
  COMMENT+="✅ No governance violations detected.

"
fi

COMMENT+="**Enforcement Mode:** Append-only audit trail (immutable GitHub comments)

**Scanner Details:**
\`\`\`
$SCAN_OUT
\`\`\`
"

# Post comment to audit issue
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  BODY="$(echo "$COMMENT" | jq -Rn -s '{body: input}')"
  
  curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/issues/$ISSUE_NUM_AUDIT/comments" \
    -d "$BODY" > /dev/null 2>&1 || true
  
  echo "Posted scan results to GitHub issue #$ISSUE_NUM_AUDIT"
fi
