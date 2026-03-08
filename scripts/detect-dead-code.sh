#!/bin/bash
#
# detect-dead-code.sh - Identify unreferenced metadata items (idempotent, no-ops)
#
# Analyzes metadata to find:
# - Workflows/scripts with no incoming dependencies
# - Items not referenced by any other items
# - Potential candidates for archival
#
# Idempotent: reads metadata, outputs analysis (no side effects)
# No-ops: pure analysis, no mutations
#
# Usage:
#   ./scripts/detect-dead-code.sh
#   ./scripts/detect-dead-code.sh --json
#   ./scripts/detect-dead-code.sh --archive-candidates
#

set -euo pipefail

METADATA_DIR="metadata"
OUTPUT_MODE="${1:-text}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
GREEN='\033[0;32m'
NC='\033[0m'

# ============================================================================
# Analysis (read-only, idempotent)
# ============================================================================

# Get all item IDs from all collections
ALL_ITEMS=$(jq -r '.workflows[]?.id, .scripts[]?.id, .secrets[]?.id' "$METADATA_DIR/items.json" | sort -u)

# Get all references from dependencies (these include file paths and IDs)
# We need to normalize and check if item ID appears anywhere in the dependencies
ALL_DEPS=$(jq -r '.dependencies[] | (.from, .to)' "$METADATA_DIR/dependencies.json" 2>/dev/null | sort -u || echo "")

# For each item, check if it's referenced anywhere in the dependency graph
UNREFERENCED=()
while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    # Check if this item ID is referenced as either "from" or "to" in dependencies
    if ! echo "$ALL_DEPS" | grep -q "^${item}$" && \
       ! echo "$ALL_DEPS" | grep -q "/${item}\."; then
        UNREFERENCED+=("$item")
    fi
done <<< "$ALL_ITEMS"

# Analyze each unreferenced item for additional context
DEAD_CODE_COUNT=0
CRITICAL_DEAD=0
HIGH_DEAD=0
MEDIUM_DEAD=0
LOW_DEAD=0

DEAD_ITEMS_JSON=$(jq -n '[
  {
    "id": "",
    "type": "",
    "risk_level": "",
    "status": "DEAD_CODE_CANDIDATE"
  }
] | .[0:0]')

while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    
    ITEM_INFO=$(jq -r --arg id "$item" '
        if (.workflows[] | select(.id == $id)) then
            (.workflows[] | select(.id == $id)) as $i |
            {type: "workflow", risk: $i.risk_level, name: $i.name}
        elif (.scripts[] | select(.id == $id)) then
            (.scripts[] | select(.id == $id)) as $i |
            {type: "script", risk: $i.risk_level, name: $i.name}
        elif (.secrets[] | select(.id == $id)) then
            (.secrets[] | select(.id == $id)) as $i |
            {type: "secret", risk: $i.risk_level}
        else
            {type: "unknown", risk: "UNKNOWN"}
        end
    ' "$METADATA_DIR/items.json")
    
    TYPE=$(echo "$ITEM_INFO" | jq -r '.type')
    RISK=$(echo "$ITEM_INFO" | jq -r '.risk // "UNKNOWN"')
    
    DEAD_CODE_COUNT=$((DEAD_CODE_COUNT + 1))
    
    case "$RISK" in
        CRITICAL) CRITICAL_DEAD=$((CRITICAL_DEAD + 1)) ;;
        HIGH) HIGH_DEAD=$((HIGH_DEAD + 1)) ;;
        MEDIUM) MEDIUM_DEAD=$((MEDIUM_DEAD + 1)) ;;
        LOW) LOW_DEAD=$((LOW_DEAD + 1)) ;;
    esac
    
    # Track for JSON output
    DEAD_ITEMS_JSON=$(echo "$DEAD_ITEMS_JSON" | jq --arg id "$item" --arg type "$TYPE" --arg risk "$RISK" '
        . += [{
            id: $id,
            type: $type,
            risk_level: $risk,
            referenced_by_count: 0
        }]
    ')
done <<< "$UNREFERENCED"

# ============================================================================
# Output Generation
# ============================================================================

if [[ "$OUTPUT_MODE" == "--json" ]]; then
    # Machine-readable JSON
    jq -n \
        --argjson total "$DEAD_CODE_COUNT" \
        --argjson critical "$CRITICAL_DEAD" \
        --argjson high "$HIGH_DEAD" \
        --argjson medium "$MEDIUM_DEAD" \
        --argjson low "$LOW_DEAD" \
        --argjson items "$DEAD_ITEMS_JSON" \
        '{
            analysis_type: "dead_code_detection",
            summary: {
                total_unreferenced_items: $total,
                by_risk_level: {
                    critical: $critical,
                    high: $high,
                    medium: $medium,
                    low: $low
                }
            },
            candidates: $items
        }'
elif [[ "$OUTPUT_MODE" == "--archive-candidates" ]]; then
    # Output safe-to-archive recommendations
    echo "$UNREFERENCED" | while read -r item; do
        [[ -z "$item" ]] && continue
        RISK=$(jq -r --arg id "$item" '
            ((.workflows[]? // .scripts[]? // .secrets[]?) | select(.id == $id) | .risk_level // "UNKNOWN") | first
        ' "$METADATA_DIR/items.json")
        
        # CRITICAL and HIGH risk items should not be archived automatically
        if [[ "$RISK" == "CRITICAL" ]] || [[ "$RISK" == "HIGH" ]]; then
            echo "⚠️  $item ($RISK) - REVIEW MANUALLY BEFORE ARCHIVAL"
        else
            echo "✓  $item ($RISK) - Safe to archive"
        fi
    done
else
    # Human-readable text output
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ DEAD CODE DETECTION REPORT${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ $DEAD_CODE_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ No unreferenced items detected${NC}"
        echo "  All workflows and scripts are properly referenced by dependencies."
    else
        echo -e "${YELLOW}⚠ Found $DEAD_CODE_COUNT unreferenced items${NC}"
        echo ""
        echo "By Risk Level:"
        echo "  CRITICAL: $CRITICAL_DEAD items"
        echo "  HIGH:     $HIGH_DEAD items"
        echo "  MEDIUM:   $MEDIUM_DEAD items"
        echo "  LOW:      $LOW_DEAD items"
        echo ""
        echo "Items without incoming dependencies:"
        echo ""
        
        echo "$UNREFERENCED" | while read -r item; do
            [[ -z "$item" ]] && continue
            
            ITEM_INFO=$(jq -r --arg id "$item" '
                if (.workflows[] | select(.id == $id)) then
                    (.workflows[] | select(.id == $id)) as $i |
                    "  workflow: \($i.name) (\($i.risk_level // "UNKNOWN"))"
                elif (.scripts[] | select(.id == $id)) then
                    (.scripts[] | select(.id == $id)) as $i |
                    "  script: \($i.id) (\($i.risk_level // "UNKNOWN"))"
                elif (.secrets[] | select(.id == $id)) then
                    (.secrets[] | select(.id == $id)) as $i |
                    "  secret: \($i.id) (\($i.risk_level // "UNKNOWN"))"
                else
                    "  unknown: \($id)"
                end
            ' "$METADATA_DIR/items.json")
            
            RISK=$(echo "$ITEM_INFO" | grep -oP '\(\K[^)]+(?=\))')
            
            if [[ "$RISK" == "CRITICAL" ]]; then
                echo -e "${RED}✗$ITEM_INFO${NC} - CRITICAL: Review before removal"
            elif [[ "$RISK" == "HIGH" ]]; then
                echo -e "${YELLOW}!$ITEM_INFO${NC} - HIGH: Verify impact before removal"
            else
                echo -e "${GREEN}○$ITEM_INFO${NC}"
            fi
        done
        echo ""
        echo "Recommendation:"
        echo "  - CRITICAL items: Must be reviewed by team before removal"
        echo "  - HIGH items: Verify impact analysis before archival"
        echo "  - MEDIUM/LOW: Safe to archive if unused externally"
    fi
fi
