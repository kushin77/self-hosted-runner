#!/bin/bash
#
# analyze-impact.sh - Analyze impact of changing/breaking an item
#
# Usage:
#   bash scripts/analyze-impact.sh --workflow terraform-apply
#   bash scripts/analyze-impact.sh --script deploy-full-stack.sh
#   bash scripts/analyze-impact.sh --secret AWS_OIDC_ROLE_ARN
#
# Output: Full impact analysis with downstream effects
#

set -euo pipefail

ITEM_TYPE=""
ITEM_NAME=""
METADATA_DIR="metadata"
OUTPUT_FORMAT="text"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workflow)
            ITEM_TYPE="workflow"
            ITEM_NAME="$2"
            shift 2
            ;;
        --script)
            ITEM_TYPE="script"
            ITEM_NAME="$2"
            shift 2
            ;;
        --secret)
            ITEM_TYPE="secret"
            ITEM_NAME="$2"
            shift 2
            ;;
        --config)
            ITEM_TYPE="config"
            ITEM_NAME="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use: --workflow NAME, --script FILE, --secret NAME, --config NAME"
            exit 1
            ;;
    esac
done

if [[ -z "$ITEM_TYPE" || -z "$ITEM_NAME" ]]; then
    echo "Error: Must specify --workflow, --script, --secret, or --config"
    exit 1
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

find_item_in_metadata() {
    local type=$1
    local name=$2
    
    if [[ "$type" == "workflow" ]]; then
        jq ".workflows[] | select(.name == \"$name\" or .id == \"$name\")" "$METADATA_DIR/items.json" 2>/dev/null || echo "null"
    elif [[ "$type" == "script" ]]; then
        jq ".scripts[] | select(.name == \"$name\" or .id == \"$name\" or .file == \"$name\")" "$METADATA_DIR/items.json" 2>/dev/null || echo "null"
    elif [[ "$type" == "secret" ]]; then
        jq ".secrets[] | select(.id == \"$name\")" "$METADATA_DIR/items.json" 2>/dev/null || echo "null"
    elif [[ "$type" == "config" ]]; then
        jq ".configuration[] | select(.id == \"$name\")" "$METADATA_DIR/items.json" 2>/dev/null || echo "null"
    fi
}

get_impacts() {
    local type=$1
    local name=$2
    
    jq ".impact_paths[] | select(.trigger | contains(\"$name\"))" "$METADATA_DIR/dependencies.json" 2>/dev/null || echo ""
}

get_dependents() {
    local type=$1
    local name=$2
    
    if [[ "$type" == "workflow" ]]; then
        jq ".dependencies[] | select(.to | contains(\"$name\"))" "$METADATA_DIR/dependencies.json" 2>/dev/null
    elif [[ "$type" == "script" ]]; then
        jq ".dependencies[] | select(.to | contains(\"$name\"))" "$METADATA_DIR/dependencies.json" 2>/dev/null
    elif [[ "$type" == "secret" ]]; then
        jq ".dependencies[] | select(.to == \"$name\")" "$METADATA_DIR/dependencies.json" 2>/dev/null
    fi
}

# ============================================================================
# TEXT OUTPUT
# ============================================================================

output_impact_analysis_text() {
    local type=$1
    local name=$2
    
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ IMPACT ANALYSIS: $type - $name${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Find in metadata
    local item=$(find_item_in_metadata "$type" "$name")
    
    if [[ "$item" == "null" || -z "$item" ]]; then
        echo -e "${RED}❌ Item not found in metadata: $name${NC}"
        echo ""
        echo "Searched for:"
        if [[ "$type" == "workflow" ]]; then
            echo "  - Workflow name: $name"
            echo "  - Workflow ID: $name"
            jq '.workflows[].name' "$METADATA_DIR/items.json" 2>/dev/null | head -5 | sed 's/^/  Available: /'
        elif [[ "$type" == "script" ]]; then
            echo "  - Script name: $name"
            echo "  - Script file: $name"
            jq '.scripts[].name' "$METADATA_DIR/items.json" 2>/dev/null | head -5 | sed 's/^/  Available: /'
        fi
        exit 1
    fi
    
    # Get owner
    local owner=$(echo "$item" | jq -r '.owner // "unknown"')
    local description=$(echo "$item" | jq -r '.description // ""')
    local risk=$(echo "$item" | jq -r '.risk_level // "UNKNOWN"')
    
    # Color code risk
    local risk_color=$NC
    if [[ "$risk" == "CRITICAL" ]]; then
        risk_color=$RED
    elif [[ "$risk" == "HIGH" ]]; then
        risk_color=$YELLOW
    fi
    
    echo -e "📌 ${BLUE}Item Details${NC}"
    echo "   Owner: $owner"
    echo "   Risk Level: ${risk_color}$risk${NC}"
    echo "   Description: $description"
    echo ""
    
    # Get dependencies
    echo -e "📊 ${BLUE}Direct Dependencies${NC} (what this depends on)"
    if [[ "$type" == "workflow" ]]; then
        local deps=$(echo "$item" | jq -r '.dependencies.scripts[]? // empty' 2>/dev/null)
        if [[ -n "$deps" ]]; then
            echo "   Scripts:"
            echo "$deps" | sed 's/^/     - /'
        fi
        
        local sec=$(echo "$item" | jq -r '.dependencies.secrets[]? // empty' 2>/dev/null)
        if [[ -n "$sec" ]]; then
            echo "   Secrets:"
            echo "$sec" | sed 's/^/     - /'
        fi
    fi
    echo ""
    
    # Get downstream impacts
    echo -e "⚠️  ${BLUE}Downstream Impact${NC} (what breaks if this fails)"
    local impacts=$(get_impacts "$type" "$name")
    if [[ -n "$impacts" ]]; then
        echo "$impacts" | jq -r '.impact[]? // empty' | sed 's/^/   - /'
        echo ""
        echo "   Time to detect: $(echo "$impacts" | jq -r '.time_to_detect // "unknown"')"
        echo "   Time to fix: $(echo "$impacts" | jq -r '.time_to_fix // "unknown"')"
        echo "   Severity: $(echo "$impacts" | jq -r '.severity // "unknown"')"
    else
        echo "   ✓ No direct downstream impacts documented"
    fi
    echo ""
    
    # Get dependents
    echo -e "🔗 ${BLUE}Dependent Items${NC} (what uses this)"
    local dependents=$(get_dependents "$type" "$name")
    if [[ -n "$dependents" ]]; then
        echo "$dependents" | jq -r '.from' | sort -u | sed 's/^/   - /'
    else
        echo "   ✓ Nothing documented as depending on this"
    fi
    echo ""
    
    # Risk assessment
    echo -e "⚡ ${BLUE}Risk Assessment${NC}"
    if [[ "$risk" == "CRITICAL" ]]; then
        echo -e "   ${RED}🚨 CRITICAL ITEM - Changes require:${NC}"
        echo "      • Full impact analysis"
        echo "      • Owner approval (@$owner)"
        echo "      • Oncall team notification"
        echo "      • Runbook review"
    elif [[ "$risk" == "HIGH" ]]; then
        echo -e "   ${YELLOW}⚠️  HIGH RISK - Changes require:${NC}"
        echo "      • Owner review (@$owner)"
        echo "      • Testing in staging"
    else
        echo "   ✓ Low risk - standard PR process"
    fi
    echo ""
    
    # Recommendations
    echo -e "💡 ${BLUE}Recommendations${NC}"
    if [[ "$ITEM_TYPE" == "secret" ]]; then
        local rotation=$(echo "$item" | jq -r '.rotation_schedule // "unknown"')
        echo "   • Rotation schedule: $rotation"
        echo "   • Check expiration date"
        echo "   • Document all callers"
    elif [[ "$ITEM_TYPE" == "workflow" ]]; then
        echo "   • Update all dependent items if renaming"
        echo "   • Test in staging before merging"
        echo "   • Notify @$owner before major changes"
    elif [[ "$ITEM_TYPE" == "script" ]]; then
        echo "   • Check all callers if interface changes"
        echo "   • Maintain backward compatibility"
        echo "   • Update documentation in metadata"
    fi
    echo ""
    
    echo -e "${GREEN}✓ Analysis complete${NC}"
    echo ""
}

# ============================================================================
# JSON OUTPUT
# ============================================================================

output_impact_analysis_json() {
    local type=$1
    local name=$2
    
    local item=$(find_item_in_metadata "$type" "$name")
    local impacts=$(get_impacts "$type" "$name")
    local dependents=$(get_dependents "$type" "$name")
    
    cat <<EOF
{
  "item": {
    "type": "$type",
    "name": "$name",
    "data": $item
  },
  "impacts": $impacts,
  "dependents": $dependents,
  "risk_level": "$(echo "$item" | jq -r '.risk_level // "UNKNOWN"')",
  "owner": "$(echo "$item" | jq -r '.owner // "unknown"')"
}
EOF
}

# ============================================================================
# MAIN
# ============================================================================

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    output_impact_analysis_json "$ITEM_TYPE" "$ITEM_NAME"
else
    output_impact_analysis_text "$ITEM_TYPE" "$ITEM_NAME"
fi
