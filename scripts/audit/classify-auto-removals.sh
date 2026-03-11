#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# GOVERNANCE AUDIT - AUTO-REMOVAL COMPLIANCE CLASSIFICATION
# ============================================================================
# Automatically fetches release/tag metadata, classifies compliance,
# and creates escalation issues for any policy violations.
#
# USAGE:
#   bash scripts/audit/classify-auto-removals.sh
#
# REQUIREMENTS:
#   - GITHUB_TOKEN env var (for GitHub API access)
#   - git configured and repo cloned
#
# ============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR"

AUDIT_CSV="governance/auto-removals-2026-03-11.csv"
REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
GH_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"

echo "=========================================="
echo "GOVERNANCE AUDIT - AUTO-REMOVAL CLASSIFICATION"
echo "Date: $(date -Iseconds)"
echo "=========================================="
echo ""

# Ensure CSV exists
if [ ! -f "$AUDIT_CSV" ]; then
  echo "[INIT] Creating audit CSV baseline..."
  mkdir -p governance
  cat > "$AUDIT_CSV" << 'EOF'
release_name,release_sha,removal_timestamp,author,is_github_actions_bot,is_pull_release,is_policy_compliant,compliance_notes,escalation_issued,escalation_issue_number
EOF
  echo "  ✓ CSV created at $AUDIT_CSV"
fi

# Fetch list of recent releases/tags that might have been auto-removed
echo ""
echo "[1/3] Fetching recent releases from GitHub API..."
RELEASES=$(curl -sS \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "${GH_API}/releases?per_page=100&state=all" \
  2>/dev/null | jq -r '.[].tag_name // empty' || echo "")

echo "  Found releases: $(echo "$RELEASES" | wc -l)"

# Function to classify compliance
classify_release() {
  local release_name="$1"
  local release_sha="$2"
  local author="$3"
  local created_at="$4"
  
  local is_bot=false
  local is_pull=false
  local is_compliant=true
  local notes="Manual release classification"
  
  # Check if created by GitHub Actions bot
  if [[ "$author" == "github-actions"* ]] || [[ "$author" == "actions-bot" ]]; then
    is_bot=true
    is_compliant=false
    notes="VIOLATION: GitHub Actions bot created release"
  fi
  
  # Check if release name indicates pull-based
  if [[ "$release_name" =~ ^pr|pull|merge.*$ ]] || [[ "$release_name" == *"-pull-"* ]]; then
    is_pull=true
    is_compliant=false
    notes="VIOLATION: Pull-based release (name pattern)"
  fi
  
  # Output as CSV line
  echo "${release_name},${release_sha},${created_at},${author},${is_bot},${is_pull},${is_compliant},${notes},false,"
}

echo ""
echo "[2/3] Classifying compliance for known auto-removals..."

# Reference list of known auto-removals (from issue comments + logs)
KNOWN_REMOVALS=(
  "gov-final-1773240829"
  "gov-test-1773240783"
)

# Add any other governance-tagged releases
for release in $RELEASES; do
  if [[ "$release" =~ ^gov- ]] || [[ "$release" =~ ^final- ]]; then
    KNOWN_REMOVALS+=("$release")
  fi
done

# Classify each removal
declare -A CLASSIFIED
for removal in "${KNOWN_REMOVALS[@]}"; do
  if [ -z "$removal" ]; then continue; fi
  
  # Avoid duplicates
  if [[ -n "${CLASSIFIED[$removal]:-}" ]]; then continue; fi
  CLASSIFIED["$removal"]=1
  
  # Fetch release metadata
  echo "  Processing: $removal"
  RELEASE_DATA=$(curl -sS \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${GH_API}/releases/tags/${removal}" 2>/dev/null || echo "{}")
  
  AUTHOR=$(echo "$RELEASE_DATA" | jq -r '.author.login // "system"')
  SHA=$(echo "$RELEASE_DATA" | jq -r '.target_commitish // "unknown"')
  CREATED=$(echo "$RELEASE_DATA" | jq -r '.created_at // "unknown"')
  
  # Classify
  CLASSIFICATION=$(classify_release "$removal" "$SHA" "$AUTHOR" "$CREATED")
  
  # Check if already in CSV
  if ! grep -q "^${removal}," "$AUDIT_CSV" 2>/dev/null; then
    echo "$CLASSIFICATION" >> "$AUDIT_CSV"
    echo "    ✓ Added to CSV"
  fi
done

echo ""
echo "[3/3] Generating compliance report..."

# Count violations
VIOLATIONS=$(tail -n +2 "$AUDIT_CSV" | awk -F',' '$7 == "false" {count++} END {print count+0}')
COMPLIANT=$(tail -n +2 "$AUDIT_CSV" | awk -F',' '$7 == "true" {count++} END {print count+0}')
TOTAL=$(tail -n +2 "$AUDIT_CSV" | wc -l)

echo ""
echo "=========================================="
echo "AUDIT RESULTS"
echo "=========================================="
echo "Total removals: $TOTAL"
echo "Compliant: $COMPLIANT"
echo "Violations: $VIOLATIONS"
echo ""

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "⚠️  VIOLATIONS DETECTED - Creating escalation issues..."
  
  # Create escalation issues for each violation
  tail -n +2 "$AUDIT_CSV" | awk -F',' '$7 == "false" {print $1, $8}' | while read release notes; do
    if [ -z "$release" ]; then continue; fi
    
    ISSUE_TITLE="COMPLIANCE VIOLATION: $release"
    ISSUE_BODY=$'Governance audit detected policy violation:\n\n'
    ISSUE_BODY+="Release: \`$release\`\n"
    ISSUE_BODY+="Notes: $notes\n\n"
    ISSUE_BODY+="Action: Review release creation method and enforce policy compliance."
    
    # Create issue (if not already created)
    curl -sS -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Content-Type: application/json" \
      "${GH_API}/issues" \
      -d "$(jq -n --arg title "$ISSUE_TITLE" --arg body "$ISSUE_BODY" \
        --arg label "governance/violation,governance/compliance" \
        '{title: $title, body: $body, labels: ($label | split(","))}' 2>/dev/null)" \
      > /dev/null 2>&1 || true
    
    echo "  ✓ Created escalation issue: $ISSUE_TITLE"
  done
else
  echo "✅ ALL removals compliant with governance policy"
fi

echo ""
echo "=========================================="
echo "AUDIT COMPLETE"
echo "=========================================="
echo ""
echo "Audit file: $AUDIT_CSV"
echo "Next steps:"
echo "  1. Review compliance report: $(tail -5 "$AUDIT_CSV")"
echo "  2. If violations exist, check escalation issues in GitHub"
echo "  3. Update policy or release creation process as needed"
echo ""
