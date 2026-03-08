#!/bin/bash
#
# Audit Workflows - Discover, validate, and report on GitHub Actions workflows
# 
# Usage:
#   bash scripts/audit-workflows.sh --full           # All workflows with details
#   bash scripts/audit-workflows.sh --search PATTERN # Find workflows matching pattern
#   bash scripts/audit-workflows.sh --category NAME  # Show workflows in category
#   bash scripts/audit-workflows.sh --trigger TYPE   # Show workflows by trigger type
#   bash scripts/audit-workflows.sh --complex        # Show high-impact workflows only
#   bash scripts/audit-workflows.sh --json           # Machine-readable JSON output
#   bash scripts/audit-workflows.sh --validate       # Check for missing workflow files
#   bash scripts/audit-workflows.sh --summary        # Quick statistics
#
# Output Formats: Text (default), JSON, HTML (if requested)
#

set -euo pipefail

OUTPUT_FORMAT="text"
SEARCH_PATTERN=""
CATEGORY_FILTER=""
TRIGGER_FILTER=""
COMPLEX_ONLY=false
VALIDATE_MODE=false
SUMMARY_ONLY=false
WORKFLOWS_DIR=".github/workflows"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            OUTPUT_FORMAT="text"
            shift
            ;;
        --search)
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        --category)
            CATEGORY_FILTER="$2"
            shift 2
            ;;
        --trigger)
            TRIGGER_FILTER="$2"
            shift 2
            ;;
        --complex)
            COMPLEX_ONLY=true
            shift
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --validate)
            VALIDATE_MODE=true
            shift
            ;;
        --summary)
            SUMMARY_ONLY=true
            shift
            ;;
        --html)
            OUTPUT_FORMAT="html"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use: --full, --search PATTERN, --category NAME, --trigger TYPE, --complex, --json, --validate, --summary"
            exit 1
            ;;
    esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

get_workflow_name() {
    local file=$1
    grep -m1 "^name:" "$file" 2>/dev/null | sed 's/name: //' | tr -d "'" | tr -d '"' || basename "$file"
}

get_workflow_category() {
    local filename=$1
    # Extract category from filename (e.g., terraform-aws-* -> terraform, runner-* -> runner)
    if [[ $filename =~ ^([a-z-]+)- ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "other"
    fi
}

get_workflow_triggers() {
    local file=$1
    # Extract trigger types
    grep "on:" -A 20 "$file" 2>/dev/null | grep -E "^\s+(schedule|push|pull_request|release|workflow_dispatch|workflow_call|issues|issue_comment)" | sed 's/:.*//' | xargs | tr ' ' ',' || echo "unknown"
}

count_workflow_jobs() {
    local file=$1
    grep "^\s\s[a-z_]*:" "$file" 2>/dev/null | grep -v "on:" | wc -l
}

has_matrix_strategy() {
    local file=$1
    grep -q "strategy:" "$file" 2>/dev/null && echo "yes" || echo "no"
}

# ============================================================================
# DISCOVERY FUNCTIONS
# ============================================================================

discover_all_workflows() {
    [ "$OUTPUT_FORMAT" != "json" ] && echo "🔍 Discovering workflows in $WORKFLOWS_DIR..." >&2
    
    find "$WORKFLOWS_DIR" -name "*.yml" -type f | sort
}

get_all_workflow_count() {
    discover_all_workflows | wc -l
}

get_workflow_by_trigger() {
    local trigger=$1
    while IFS= read -r file; do
        triggers=$(get_workflow_triggers "$file")
        if [[ "$triggers" == *"$trigger"* ]]; then
            echo "$file"
        fi
    done < <(discover_all_workflows)
}

get_workflow_by_category() {
    local category=$1
    while IFS= read -r file; do
        wf_category=$(get_workflow_category "$(basename "$file")")
        if [[ "$wf_category" == "$category" ]]; then
            echo "$file"
        fi
    done < <(discover_all_workflows)
}

get_complex_workflows() {
    # Workflows with matrix strategy or many jobs = high-impact
    while IFS= read -r file; do
        jobs=$(count_workflow_jobs "$file")
        if [[ $jobs -gt 3 ]]; then
            echo "$file"
        fi
    done < <(discover_all_workflows)
}

search_workflows() {
    local pattern=$1
    while IFS= read -r file; do
        if [[ "$(basename "$file")" == *"$pattern"* ]] || grep -q "$pattern" "$file" 2>/dev/null; then
            echo "$file"
        fi
    done < <(discover_all_workflows)
}

# ============================================================================
# TEXT OUTPUT FORMAT
# ============================================================================

output_workflow_text() {
    local file=$1
    local name=$(get_workflow_name "$file")
    local triggers=$(get_workflow_triggers "$file")
    local jobs=$(count_workflow_jobs "$file")
    local matrix=$(has_matrix_strategy "$file")
    local category=$(get_workflow_category "$(basename "$file")")
    
    echo -e "${BLUE}📋 $name${NC}"
    echo "   File: $file"
    echo "   Category: $category | Jobs: $jobs | Matrix: $matrix"
    echo "   Triggers: $triggers"
    echo ""
}

output_summary_text() {
    local count=$1
    local scheduled=$(get_workflow_by_trigger "schedule" | wc -l)
    local dispatch=$(get_workflow_by_trigger "workflow_dispatch" | wc -l)
    local push=$(get_workflow_by_trigger "push" | wc -l)
    local pr=$(get_workflow_by_trigger "pull_request" | wc -l)
    
    echo -e "${GREEN}=== WORKFLOW AUDIT SUMMARY ===${NC}"
    echo "Total Workflows: $count"
    echo ""
    echo "By Trigger Type:"
    echo "  Scheduled (cron):          $scheduled"
    echo "  Manual dispatch:           $dispatch"
    echo "  Push/commit:               $push"
    echo "  Pull Request:              $pr"
    echo ""
    
    # Show categories
    echo "By Category:"
    for file in "$WORKFLOWS_DIR"/*.yml; do
        basename_only=$(basename "$file")
        if [[ $basename_only =~ ^([a-z-]+)- ]]; then
            echo "${BASH_REMATCH[1]}"
        else
            echo "other"
        fi
    done 2>/dev/null | sort | uniq -c | awk '{print "  " $2 ": " $1}'
    echo ""
}

# ============================================================================
# JSON OUTPUT FORMAT
# ============================================================================

output_workflow_json() {
    local file=$1
    local name=$(get_workflow_name "$file")
    local triggers=$(get_workflow_triggers "$file")
    local jobs=$(count_workflow_job "$file")
    local category=$(get_workflow_category "$(basename "$file")")
    
    cat <<EOF
{
  "file": "$file",
  "name": "$name",
  "category": "$category",
  "triggers": "$triggers",
  "job_count": $jobs
}
EOF
}

output_all_workflows_json() {
    echo "["
    local first=true
    while IFS= read -r file; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        output_workflow_json "$file" 2>/dev/null | tr '\n' ' '
    done < <(discover_all_workflows)
    echo ""
    echo "]"
}

# ============================================================================
# HTML OUTPUT FORMAT
# ============================================================================

output_html_header() {
    cat <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Workflow Audit Report</title>
    <style>
        body { font-family: Arial; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; }
        .scheduled { background-color: #fff3cd; }
        .manual { background-color: #d1ecf1; }
        .summary { margin: 20px 0; padding: 15px; background-color: #f8f9fa; border-left: 4px solid #007bff; }
    </style>
</head>
<body>
    <h1>🔍 GitHub Workflows Audit Report</h1>
EOF
}

output_html_footer() {
    cat <<'EOF'
    <p><em>Generated: $(date)</em></p>
</body>
</html>
EOF
}

# ============================================================================
# VALIDATION MODE
# ============================================================================

validate_workflows() {
    [ "$OUTPUT_FORMAT" != "json" ] && echo "✓ Validating workflows..." >&2
    
    local errors=0
    
    while IFS= read -r file; do
        # Check if file exists and is readable
        if [[ ! -r "$file" ]]; then
            echo "❌ Cannot read: $file"
            ((errors++))
            continue
        fi
        
        # Check for required 'name' field
        if ! grep -q "^name:" "$file"; then
            echo "⚠️  Missing 'name' field: $file"
            ((errors++))
        fi
        
        # Check for at least one trigger
        if ! grep -q "^on:" "$file"; then
            echo "❌ Missing 'on' trigger section: $file"
            ((errors++))
        fi
        
        # Check YAML syntax
        if ! grep -q "^jobs:" "$file"; then
            echo "❌ Missing 'jobs' section: $file"
            ((errors++))
        fi
    done < <(discover_all_workflows)
    
    local total=$(get_all_workflow_count)
    local valid=$((total - errors))
    
    echo ""
    [ "$OUTPUT_FORMAT" != "json" ] && echo "Validation Summary:"
    [ "$OUTPUT_FORMAT" != "json" ] && echo "  Total workflows: $total"
    [ "$OUTPUT_FORMAT" != "json" ] && echo "  Valid workflows: $valid"
    [ "$OUTPUT_FORMAT" != "json" ] && echo "  Issues found: $errors"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    if [[ "$VALIDATE_MODE" == true ]]; then
        validate_workflows
        exit 0
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_all_workflows_json
        exit 0
    fi
    
    if [[ "$SUMMARY_ONLY" == true ]]; then
        total=$(get_all_workflow_count)
        output_summary_text "$total"
        exit 0
    fi
    
    # Build workflow list based on filters
    if [[ -n "$SEARCH_PATTERN" ]]; then
        workflows=$(search_workflows "$SEARCH_PATTERN")
    elif [[ -n "$CATEGORY_FILTER" ]]; then
        workflows=$(get_workflow_by_category "$CATEGORY_FILTER")
    elif [[ -n "$TRIGGER_FILTER" ]]; then
        workflows=$(get_workflow_by_trigger "$TRIGGER_FILTER")
    elif [[ "$COMPLEX_ONLY" == true ]]; then
        workflows=$(get_complex_workflows)
    else
        workflows=$(discover_all_workflows)
    fi
    
    # Output workflows
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        output_workflow_text "$file"
    done <<< "$workflows"
    
    # Summary footer
    total=$(get_all_workflow_count)
    count=$(echo "$workflows" | grep -c "." || true)
    echo ""
    echo "Found: $count workflow(s) out of $total total"
}

main "$@"
