#!/bin/bash
#
# Audit Scripts - Discover, validate, and report on all scripts in the repository
#
# Usage:
#   bash scripts/audit-scripts.sh --full            # All scripts with details
#   bash scripts/audit-scripts.sh --search PATTERN  # Find scripts matching pattern
#   bash scripts/audit-scripts.sh --category CAT    # Show scripts in category
#   bash scripts/audit-scripts.sh --critical        # Show critical scripts only
#   bash scripts/audit-scripts.sh --dependencies    # Show script dependencies
#   bash scripts/audit-scripts.sh --json            # Machine-readable JSON
#   bash scripts/audit-scripts.sh --validate        # Check script integrity
#   bash scripts/audit-scripts.sh --summary         # Quick statistics
#
# Output Formats: Text (default), JSON, HTML (if requested)
#

set -euo pipefail

OUTPUT_FORMAT="text"
SEARCH_PATTERN=""
CATEGORY_FILTER=""
CRITICAL_ONLY=false
VALIDATE_MODE=false
SUMMARY_ONLY=false
DEPENDENCIES_MODE=false
SCRIPTS_DIR="scripts"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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
        --critical)
            CRITICAL_ONLY=true
            shift
            ;;
        --dependencies)
            DEPENDENCIES_MODE=true
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
            echo "Use: --full, --search, --category, --critical, --dependencies, --json, --validate, --summary"
            exit 1
            ;;
    esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

get_script_category() {
    local script=$1
    local basename=$(basename "$script")
    
    # Categorize based on script name/location
    if [[ $basename =~ ^terraform ]]; then
        echo "terraform"
    elif [[ $basename =~ ^deploy ]]; then
        echo "deployment"
    elif [[ $basename =~ ^runner ]]; then
        echo "runners"
    elif [[ $basename =~ ^monitor|health ]]; then
        echo "monitoring"
    elif [[ $basename =~ ^validate|test|check ]]; then
        echo "validation"
    elif [[ $basename =~ ^audit ]]; then
        echo "audit"
    elif [[ $basename =~ ^security|rotate|cert ]]; then
        echo "security"
    elif [[ $basename =~ ^backup|restore|sync ]]; then
        echo "backup"
    elif [[ $basename =~ ^install|setup|init ]]; then
        echo "infrastructure"
    elif [[ $basename =~ ^cleanup|delete ]]; then
        echo "maintenance"
    else
        echo "utilities"
    fi
}

get_script_risk_level() {
    local script=$1
    local basename=$(basename "$script")
    
    # Identify critical scripts
    if [[ $basename =~ terraform-apply|deploy-prod|delete|cleanup|rotate-|bootstrap ]]; then
        echo "CRITICAL"
    elif [[ $basename =~ terraform-plan|deploy|terraform|runner ]]; then
        echo "HIGH"
    elif [[ $basename =~ validate|check|test ]]; then
        echo "MEDIUM"
    else
        echo "LOW"
    fi
}

count_script_lines() {
    local script=$1
    wc -l < "$script" 2>/dev/null || echo "0"
}

script_uses_sudo() {
    local script=$1
    grep -q "sudo" "$script" 2>/dev/null && echo "yes" || echo "no"
}

script_has_error_handling() {
    local script=$1
    grep -q "set -e\|set -u\|trap\|err_handler" "$script" 2>/dev/null && echo "yes" || echo "no"
}

get_script_shebang() {
    local script=$1
    head -n 1 "$script" | sed 's/^#!//'
}

get_script_description() {
    local script=$1
    # Extract first comment line after shebang
    grep -m1 "^#" "$script" 2>/dev/null | sed 's/^# //' | head -c 60
}

find_scripts_calling() {
    local target_script=$1
    local target_name=$(basename "$target_script")
    
    find "$SCRIPTS_DIR" -type f -executable ! -name "$target_name" 2>/dev/null | while read script; do
        if grep -q "$target_name" "$script" 2>/dev/null; then
            echo "$script"
        fi
    done
}

find_scripts_called_by() {
    local source_script=$1
    grep "^\s*bash\|^\s*source\|^\s*\." "$source_script" 2>/dev/null | grep -oE "[a-zA-Z0-9_-]+\.sh" | sort -u
}

# ============================================================================
# DISCOVERY FUNCTIONS
# ============================================================================

discover_all_scripts() {
    [ "$OUTPUT_FORMAT" != "json" ] && echo "🔍 Discovering executable scripts in $SCRIPTS_DIR..." >&2
    
    find "$SCRIPTS_DIR" -type f -executable | sort
}

get_all_script_count() {
    discover_all_scripts | wc -l
}

get_scripts_by_category() {
    local category=$1
    while IFS= read -r script; do
        script_category=$(get_script_category "$script")
        if [[ "$script_category" == "$category" ]]; then
            echo "$script"
        fi
    done < <(discover_all_scripts)
}

get_critical_scripts() {
    while IFS= read -r script; do
        risk=$(get_script_risk_level "$script")
        if [[ "$risk" == "CRITICAL" || "$risk" == "HIGH" ]]; then
            echo "$script"
        fi
    done < <(discover_all_scripts)
}

search_scripts() {
    local pattern=$1
    while IFS= read -r script; do
        basename_only=$(basename "$script")
        if [[ "$basename_only" == *"$pattern"* ]] || grep -q "$pattern" "$script" 2>/dev/null; then
            echo "$script"
        fi
    done < <(discover_all_scripts)
}

# ============================================================================
# TEXT OUTPUT FORMAT
# ============================================================================

output_script_text() {
    local script=$1
    local basename=$(basename "$script")
    local category=$(get_script_category "$script")
    local risk=$(get_script_risk_level "$script")
    local lines=$(count_script_lines "$script")
    local sudo=$(script_uses_sudo "$script")
    local error=$(script_has_error_handling "$script")
    local shebang=$(get_script_shebang "$script")
    local desc=$(get_script_description "$script")
    
    # Color code risk level
    local risk_color=$NC
    if [[ "$risk" == "CRITICAL" ]]; then
        risk_color=$RED
    elif [[ "$risk" == "HIGH" ]]; then
        risk_color=$YELLOW
    fi
    
    echo -e "${BLUE}📜 $basename${NC}"
    echo "   Path: $script"
    echo "   Category: $category | Risk: ${risk_color}$risk${NC} | Lines: $lines"
    echo "   Shell: $shebang | Sudo: $sudo | Error handling: $error"
    [[ -n "$desc" ]] && echo "   Description: $desc"
    echo ""
}

output_summary_text() {
    local count=$1
    
    echo -e "${GREEN}=== SCRIPT AUDIT SUMMARY ===${NC}"
    echo "Total Scripts: $count"
    echo ""
    
    # Count by category
    echo "By Category:"
    discover_all_scripts | while read script; do
        get_script_category "$script"
    done | sort | uniq -c | awk '{print "  " $2 ": " $1}'
    echo ""
    
    # Count by risk
    echo "By Risk Level:"
    critical=$(get_critical_scripts | wc -l)
    echo "  CRITICAL: $critical"
    echo "  (Review first!)"
    echo ""
    
    # Stats
    echo "Statistics:"
    with_sudo=$(discover_all_scripts | xargs -I {} bash -c "grep -q 'sudo' {} && echo {}" | wc -l)
    echo "  Scripts using sudo: $with_sudo"
    
    with_error=$(discover_all_scripts | xargs -I {} bash -c "grep -q 'set -e' {} && echo {}" | wc -l)
    echo "  Scripts with error handling (set -e): $with_error"
    echo ""
}

# ============================================================================
# JSON OUTPUT FORMAT
# ============================================================================

output_script_json() {
    local script=$1
    local basename=$(basename "$script")
    local category=$(get_script_category "$script")
    local risk=$(get_script_risk_level "$script")
    local lines=$(count_script_lines "$script")
    
    cat <<EOF
{
  "path": "$script",
  "name": "$basename",
  "category": "$category",
  "risk_level": "$risk",
  "lines": $lines
}
EOF
}

output_all_scripts_json() {
    echo "["
    local first=true
    while IFS= read -r script; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        output_script_json "$script" 2>/dev/null | tr '\n' ' '
    done < <(discover_all_scripts)
    echo ""
    echo "]"
}

# ============================================================================
# DEPENDENCIES MODE
# ============================================================================

output_dependencies() {
    echo -e "${PURPLE}=== SCRIPT DEPENDENCIES ===${NC}"
    echo ""
    
    while IFS= read -r script; do
        basename=$(basename "$script")
        
        # Scripts that call this script
        callers=$(find_scripts_calling "$script")
        if [[ -n "$callers" ]]; then
            echo -e "${BLUE}📍 $basename${NC} is called by:"
            while IFS= read -r caller; do
                echo "   └─ $(basename "$caller")"
            done <<< "$callers"
        fi
    done < <(get_critical_scripts)
    echo ""
}

# ============================================================================
# VALIDATION MODE
# ============================================================================

validate_scripts() {
    [ "$OUTPUT_FORMAT" != "json" ] && echo "✓ Validating scripts..." >&2
    
    local errors=0
    
    while IFS= read -r script; do
        # Check if file is executable
        if [[ ! -x "$script" ]]; then
            echo "❌ Not executable: $script"
            ((errors++))
            continue
        fi
        
        # Check for shebang
        if ! head -n 1 "$script" | grep -q "^#!"; then
            echo "⚠️  Missing shebang: $script"
            ((errors++))
        fi
        
        # Check syntax based on shebang
        shebang=$(get_script_shebang "$script")
        if [[ "$shebang" == *python* ]]; then
            if ! python3 -m py_compile "$script" 2>/dev/null; then
                echo "❌ Syntax error (python): $script"
                ((errors++))
            fi
        else
            if ! bash -n "$script" 2>/dev/null; then
                echo "❌ Syntax error: $script"
                ((errors++))
            fi
        fi
        
        # Warn if no error handling
        if ! grep -q "set -e\|trap\|err_handler" "$script" 2>/dev/null; then
            echo "⚠️  No error handling (set -e): $script"
            # Don't count as critical error
        fi
    done < <(discover_all_scripts)
    
    local total=$(get_all_script_count)
    local valid=$((total - errors))
    
    echo ""
    [ "$OUTPUT_FORMAT" != "json" ] && echo "Validation Summary:"
    [ "$OUTPUT_FORMAT" != "json" ] && echo "  Total scripts: $total"
    [ "$OUTPUT_FORMAT" != "json" ] && echo "  Valid scripts: $valid"
    [ "$OUTPUT_FORMAT" != "json" ] && echo "  Errors found: $errors"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    if [[ "$VALIDATE_MODE" == true ]]; then
        validate_scripts
        exit 0
    fi
    
    if [[ "$DEPENDENCIES_MODE" == true ]]; then
        output_dependencies
        exit 0
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_all_scripts_json
        exit 0
    fi
    
    if [[ "$SUMMARY_ONLY" == true ]]; then
        total=$(get_all_script_count)
        output_summary_text "$total"
        exit 0
    fi
    
    # Build script list based on filters
    if [[ -n "$SEARCH_PATTERN" ]]; then
        scripts=$(search_scripts "$SEARCH_PATTERN")
    elif [[ -n "$CATEGORY_FILTER" ]]; then
        scripts=$(get_scripts_by_category "$CATEGORY_FILTER")
    elif [[ "$CRITICAL_ONLY" == true ]]; then
        scripts=$(get_critical_scripts)
    else
        scripts=$(discover_all_scripts)
    fi
    
    # Output scripts
    while IFS= read -r script; do
        [[ -z "$script" ]] && continue
        output_script_text "$script"
    done <<< "$scripts"
    
    # Summary footer
    total=$(get_all_script_count)
    count=$(echo "$scripts" | grep -c "." || true)
    echo ""
    echo "Found: $count script(s) out of $total total"
}

main "$@"
