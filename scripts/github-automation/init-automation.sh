#!/bin/bash
# Initialize GitHub Issue Automation Framework
# Complete setup in one command

set -e

REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
    REPO="${1:?Usage: init-automation.sh [owner/repo]}"
fi

echo "🚀 Initializing GitHub Issue Automation Framework"
echo "   Repository: $REPO"
echo ""

# Step 1: Create labels
echo "Step 1/5: Creating labels..."
if bash scripts/github-automation/setup-labels.sh "$REPO" 2>/dev/null; then
    echo "✓ Labels created"
else
    echo "⚠️  Label creation had issues (may already exist)"
fi

# Step 2: Enable workflows
echo ""
echo "Step 2/5: Enabling workflows..."
WORKFLOWS_DIR=".github/workflows"
if [ -d "$WORKFLOWS_DIR" ]; then
    workflow_count=$(ls $WORKFLOWS_DIR/*.yml 2>/dev/null | wc -l)
    echo "✓ Found $workflow_count workflow files in $WORKFLOWS_DIR"
    echo "   ⚠️  Enable these manually in Settings → Actions"
else
    echo "✗ Workflows directory not found"
fi

# Step 3: Triage existing issues
echo ""
echo "Step 3/5: Triaging existing issues..."
if bash scripts/github-automation/triage-issues.sh "$REPO" 2>/dev/null; then
    echo "✓ Existing issues triaged"
else
    echo "⚠️  Some issues couldn't be triaged"
fi

# Step 4: Create example issues
echo ""
echo "Step 4/5: Creating example issues..."
echo "   Creating example bug..."
gh issue create --repo "$REPO" \
    --title "Example: SQL injection vulnerability in search" \
    --body "## Description
This is an example security issue created during automation setup.

Type: security

## Steps to Reproduce
The search endpoint doesn't properly escape user input.

## Expected Behavior
Input should be sanitized before use in queries.

## Actual Behavior
User input passed directly to SQL query." \
    --label "type:security" 2>/dev/null || echo "   ⚠️ Could not create example issue"

echo "   Creating example feature..."
gh issue create --repo "$REPO" \
    --title "Example: Add dark mode support" \
    --body "## Description
Add dark mode support to the UI

## Priority
P2

## Acceptance Criteria
- [ ] Settings page has dark mode toggle
- [ ] Theme preference persists" \
    --label "type:feature,priority:p2" 2>/dev/null || echo "   ⚠️ Could not create example issue"

echo "✓ Example issues created"

# Step 5: Display next steps
echo ""
echo "Step 5/5: Setup complete!"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. ⚙️ Enable Workflows"
echo "   Go to: Settings → Actions → General"
echo "   Select: Allow all actions and reusable workflows"
echo ""
echo "2. 🧪 Test the automation"
echo "   Create a new issue with label: type:security"
echo "   It should auto-escalate to P0 within minutes"
echo ""
echo "3. 📊 Try the CLI tool"
echo "   python3 tools/issue-cli/issue-cli.py list --state open"
echo "   python3 tools/issue-cli/issue-cli.py velocity --days 7"
echo "   python3 tools/issue-cli/issue-cli.py sla"
echo ""
echo "4. 📖 Read the documentation"
echo "   docs/GITHUB_ISSUE_AUTOMATION_README.md"
echo "   docs/ISSUE_TAXONOMY.md"
echo ""
echo "5. ✅ Validate setup"
echo "   bash scripts/github-automation/validate-automation.sh $REPO"
echo ""
echo "🎉 Automation framework ready!"
