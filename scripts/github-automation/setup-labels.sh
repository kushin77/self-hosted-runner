#!/bin/bash
# Setup GitHub labels for issue automation

set -e

REPO="${1:?Usage: setup-labels.sh <owner/repo>}"
GH_REPO="--repo $REPO"

echo "🏷️ Setting up labels for $REPO..."

# Define colors (GitHub label colors)
declare -A label_colors=(
    ["state:backlog"]="e2e2e2"      # Gray
    ["state:in-progress"]="0075ca"  # Blue
    ["state:review"]="9900ff"       # Purple
    ["state:blocked"]="ff0000"      # Red
    ["state:done"]="28a745"         # Green
    
    ["type:bug"]="ee0701"           # Red
    ["type:feature"]="a2eeef"       # Cyan
    ["type:dependencies"]="fbca04"  # Yellow
    ["type:chore"]="e4e669"         # Light Yellow
    ["type:security"]="ff0000"      # Red (bold)
    ["type:compliance"]="d73a49"    # Dark Red
    
    ["priority:p0"]="ff0000"        # Red
    ["priority:p1"]="ff5722"        # Orange
    ["priority:p2"]="ffc107"        # Amber
    ["priority:p3"]="8bc34a"        # Light Green
    ["priority:p4"]="c0c0c0"        # Gray
    ["priority:urgent"]="ff0000"    # Red
    
    ["severity:critical"]="ff0000"  # Red
    ["severity:high"]="ff8c00"      # Dark Orange
    ["severity:medium"]="ffa500"    # Orange
    ["severity:low"]="ffeb3b"       # Yellow
    
    ["sla:breached"]="ff0000"       # Red
    ["sla:critical-1d"]="ff0000"    # Red
    ["sla:high-3d"]="ff8c00"        # Dark Orange
    ["sla:medium-7d"]="ffa500"      # Orange
    ["sla:low-14d"]="ffeb3b"        # Yellow
    
    ["blocked-by-issues"]="d73a49"  # Dark Red
    ["blocks-other-issues"]="ff6f00"# Dark Orange
    ["duplicate"]="cfd3d7"          # Gray
    ["related-issue"]="cfd3d7"      # Gray
    
    ["stale"]="959da5"              # Gray
    ["breaking-change"]="d73a49"    # Dark Red
    ["wontfix"]="d3d3d3"            # Light Gray
    ["help-wanted"]="33aa3f"        # Green
)

declare -A label_descriptions=(
    ["state:backlog"]="Issue in backlog, not yet started"
    ["state:in-progress"]="Someone is actively working on this"
    ["state:review"]="PR submitted, awaiting review"
    ["state:blocked"]="Blocked by other issue(s)"
    ["state:done"]="Complete, pending release"
    
    ["type:bug"]="Something isn't working"
    ["type:feature"]="New feature or enhancement"
    ["type:dependencies"]="Dependency update or audit"
    ["type:chore"]="Refactoring or maintenance"
    ["type:security"]="Security vulnerability"
    ["type:compliance"]="Compliance or audit requirement"
    
    ["priority:p0"]="Critical priority - 12 hour SLA"
    ["priority:p1"]="High priority - 3 day SLA"
    ["priority:p2"]="Medium priority - 7 day SLA"
    ["priority:p3"]="Low priority - 30 day SLA"
    ["priority:p4"]="Minimal priority - 90 day SLA"
    ["priority:urgent"]="SLA breached - urgent action needed"
    
    ["severity:critical"]="System down or data corruption"
    ["severity:high"]="Major feature broken"
    ["severity:medium"]="Partial breakage, has workaround"
    ["severity:low"]="Minor cosmetic issue"
    
    ["sla:breached"]="SLA response time exceeded"
    ["sla:critical-1d"]="Critical SLA: 1 day"
    ["sla:high-3d"]="High SLA: 3 days"
    ["sla:medium-7d"]="Medium SLA: 7 days"
    ["sla:low-14d"]="Low SLA: 14 days"
    
    ["blocked-by-issues"]="Waiting on other issue(s)"
    ["blocks-other-issues"]="This blocks other issue(s)"
    ["duplicate"]="Duplicate of another issue"
    ["related-issue"]="Related to another issue"
    
    ["stale"]="No activity for 60+ days"
    ["breaking-change"]="Contains breaking changes"
    ["wontfix"]="Will not be fixed"
    ["help-wanted"]="Seeking community contributions"
)

# Create or update labels
count=0
for label in "${!label_colors[@]}"; do
    color="${label_colors[$label]}"
    description="${label_descriptions[$label]}"
    
    # Try to create label
    if gh label create "$label" \
        $GH_REPO \
        --color "$color" \
        --description "$description" 2>/dev/null; then
        echo "✓ Created label: $label"
        ((count++))
    else
        # If creation fails, might exist, try update
        gh label edit "$label" \
            $GH_REPO \
            --color "$color" \
            --description "$description" 2>/dev/null || true
        echo "✓ Label exists: $label"
    fi
done

echo ""
echo "✅ Finished! Created/updated $count labels"
echo ""
echo "Next steps:"
echo "1. Enable workflows: Enable all .github/workflows/*.yml in GitHub"
echo "2. Test on an issue: gh issue create --title 'Test issue' --label type:feature"
echo "3. Try CLI: python3 tools/issue-cli/issue-cli.py list --state open"
