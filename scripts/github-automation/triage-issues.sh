#!/bin/bash
# Bulk triage issues and apply governance rules

set -e

REPO="${1:?Usage: triage-issues.sh <owner/repo>}"
GH_REPO="--repo $REPO"

echo "🔍 Triaging issues in $REPO..."

# Find all open issues without state labels and apply default state:backlog
echo ""
echo "Step 1: Labeling unlabeled issues..."
gh issue list $GH_REPO --state open --json number,labels --limit 500 | \
jq -r '.[] | select(.labels | length == 0) | .number' | \
while read issue_num; do
    echo "  Adding labels to #$issue_num..."
    gh issue edit "$issue_num" $GH_REPO \
        --add-label "state:backlog,type:feature" 2>/dev/null || true
done

# Find security issues without P0
echo ""
echo "Step 2: Escalating security issues to P0..."
gh issue list $GH_REPO --state open --label "type:security" \
    --json number,labels --limit 100 | \
jq -r '.[] | select(.labels | map(.name) | index("priority:p0") | not) | .number' | \
while read issue_num; do
    echo "  Setting #$issue_num to P0..."
    gh issue edit "$issue_num" $GH_REPO --add-label "priority:p0" 2>/dev/null || true
done

# Find issues over 60 days old in backlog
echo ""
echo "Step 3: Finding stale backlog issues..."
gh issue list $GH_REPO --state open --label "state:backlog" \
    --json number,title,createdAt --limit 500 | \
jq -r '.[] | select(.createdAt | fromdate < (now - (60 * 24 * 3600))) | .number' | \
while read issue_num; do
    echo "  Marking #$issue_num as stale..."
    gh issue edit "$issue_num" $GH_REPO --add-label "stale" 2>/dev/null || true
done

# Assign security/compliance issues to main reviewer
echo ""
echo "Step 4: Assigning security/compliance issues to akushnir..."
gh issue list $GH_REPO --state open \
    --label "type:security,type:compliance" \
    --json number,assignees --limit 100 | \
jq -r '.[] | select(.assignees | length == 0) | .number' | \
while read issue_num; do
    echo "  Assigning #$issue_num..."
    gh issue edit "$issue_num" $GH_REPO --add-assignee "akushnir" 2>/dev/null || true
done

echo ""
echo "✅ Triage complete!"
echo ""
echo "Summary:"
gh issue list $GH_REPO --state open --json labels --limit 500 | \
jq '[.[] | .labels[].name] | group_by(.) | map({label: .[0], count: length}) | sort_by(-.count) | .[:20][]' | \
head -20
