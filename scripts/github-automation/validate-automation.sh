#!/bin/bash
# Validate issue automation setup

set -e

REPO="${1:?Usage: validate-automation.sh <owner/repo>}"
GH_REPO="--repo $REPO"

echo "🔍 Validating issue automation setup..."
echo ""

# Check 1: Verify workflows exist
echo "✓ Checking workflows..."
required_workflows=(
    "issue-auto-label.yml"
    "milestone-enforcement.yml"
    "sla-monitoring.yml"
    "dependency-tracking.yml"
    "pr-issue-linking.yml"
)

for workflow in "${required_workflows[@]}"; do
    if [ -f ".github/workflows/$workflow" ]; then
        echo "  ✓ $workflow exists"
    else
        echo "  ✗ $workflow missing!"
    fi
done

# Check 2: Verify labels exist
echo ""
echo "✓ Checking labels..."
required_labels=(
    "state:backlog"
    "state:in-progress"
    "state:review"
    "state:blocked"
    "state:done"
    "type:bug"
    "type:feature"
    "type:security"
    "type:compliance"
    "priority:p0"
    "priority:p1"
    "priority:p2"
)

missing_labels=0
# Fetch existing labels robustly (prefer API + jq, fallback to gh label list)
if command -v jq >/dev/null 2>&1; then
    existing_labels=$(gh api repos/$REPO/labels --paginate 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
else
    existing_labels=$(gh label list $GH_REPO 2>/dev/null | awk -F"\t" '{print $1}' 2>/dev/null || true)
fi

for label in "${required_labels[@]}"; do
    alt_label="$label"
    if [[ "$label" == *":"* ]]; then
        alt_label="${label#*:}"
    fi

    if echo "$existing_labels" | grep -xF -- "$label" >/dev/null 2>&1 || \
       echo "$existing_labels" | grep -xF -- "$alt_label" >/dev/null 2>&1; then
        echo "  ✓ $label exists (matched: ${label} or ${alt_label})"
    else
        echo "  ✗ $label missing!"
        ((missing_labels++))
    fi
done

if [ $missing_labels -gt 0 ]; then
    echo ""
    echo "⚠️ Run setup-labels.sh to create missing labels:"
    echo "   ./scripts/github-automation/setup-labels.sh $REPO"
fi

# Check 3: Test issue lifecycle
echo ""
echo "✓ Checking issue lifecycle..."

# Allow skipping live test issue creation in CI by setting SKIP_ISSUE_TEST=true
if [ "${SKIP_ISSUE_TEST:-}" = "true" ]; then
    echo "  ⚠️ Skipping live test issue creation (SKIP_ISSUE_TEST=true)"
else
    test_issue=$(gh issue create $GH_REPO \
        --title "Test: Automation Setup Validation $(date +%s)" \
        --body "This is a test issue for validation" \
        --draft 2>/dev/null | grep -oP '#\d+' | cut -c2-)

    if [ -n "$test_issue" ]; then
        echo "  ✓ Created test issue #$test_issue"
        
        # Check labels were applied
        sleep 2
        labels=$(gh issue view "$test_issue" $GH_REPO --json labels --jq '.labels[].name' 2>/dev/null | wc -l)
        
        if [ "$labels" -gt 0 ]; then
            echo "  ✓ Auto-labeling works ($(echo $labels | tr -d '[:space:]') labels applied)"
        else
            echo "  ⚠️ Auto-labeling may not be working"
        fi
        
        # Clean up
        gh issue close "$test_issue" $GH_REPO 2>/dev/null
        echo "  ✓ Cleaned up test issue"
    else
        echo "  ✗ Could not create test issue"
    fi
fi

# Check 4: Verify CLI tool
echo ""
echo "✓ Checking CLI tool..."
if [ -f "tools/issue-cli/issue-cli.py" ]; then
    echo "  ✓ CLI tool exists"
    if python3 tools/issue-cli/issue-cli.py --help >/dev/null 2>&1; then 
        echo "  ✓ CLI tool is executable"
    else
        echo "  ⚠️ CLI tool may have issues"
    fi
else
    echo "  ✗ CLI tool missing!"
fi

# Summary
echo ""
echo "✅ Validation complete!"
echo ""
echo "Next steps:"
echo "1. Enable workflows in GitHub Settings → Actions"
echo "2. Test CLI: python3 tools/issue-cli/issue-cli.py list --state open"
echo "3. Create a test issue and watch it auto-label"
echo "4. Check workflow runs in Actions tab"
