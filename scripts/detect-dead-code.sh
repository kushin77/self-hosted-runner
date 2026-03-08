#!/bin/bash
#
# detect-dead-code.sh - Identify unreferenced metadata items (idempotent, no-ops)
#
# Analyzes metadata to find items not referenced in the dependency graph
#
# Usage:
#   ./scripts/detect-dead-code.sh        # text output
#   ./scripts/detect-dead-code.sh --json # JSON output
#

set +e  # Disable exit on error for grep operations
METADATA_DIR="metadata"
OUTPUT_MODE="${1:-text}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

# Get all items
ALL_ITEMS=$(jq -r '.workflows[]?.id, .scripts[]?.id, .secrets[]?.id' "$METADATA_DIR/items.json" | sort -u)
ALL_DEPS=$(jq -r '.dependencies[] | (.from, .to)' "$METADATA_DIR/dependencies.json" 2>/dev/null | sort -u)

# Find unreferenced items
UNREFERENCED_LIST=""
CRITICAL_COUNT=0
HIGH_COUNT=0
TOTAL_COUNT=0

while IFS= read -r item; do
    if [[ -z "$item" ]]; then
        continue
    fi
    
    # Check if item is referenced in dependencies
    if echo "$ALL_DEPS" | grep -qE "(^|/)${item}($|\.|-\.yml)"; then
        continue  # Item is referenced
    fi
    
    # Item is not referenced
    UNREFERENCED_LIST="${UNREFERENCED_LIST}${item}
"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    # Get risk level
    RISK=$(jq -r --arg id "$item" '
((.workflows[] // .scripts[] // .secrets[]) | select(.id == $id) | .risk_level) // "UNKNOWN"
    ' "$METADATA_DIR/items.json" 2>/dev/null || echo "UNKNOWN")
    
    case "$RISK" in
        CRITICAL) CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
        HIGH) HIGH_COUNT=$((HIGH_COUNT + 1)) ;;
    esac
done <<< "$ALL_ITEMS"

# Output based on mode
if [[ "$OUTPUT_MODE" == "--json" ]]; then
    # Generate JSON output
    ITEMS_JSON=$(echo "$UNREFERENCED_LIST" | while read item; do
        [[ -z "$item" ]] && continue
        RISK=$(jq -r --arg id "$item" '((.workflows[] // .scripts[] // .secrets[]) | select(.id == $id) | .risk_level) // "UNKNOWN"' "$METADATA_DIR/items.json" 2>/dev/null || echo "UNKNOWN")
        TYPE=$(jq -r --arg id "$item" 'if (.workflows[] | select(.id == $id)) then "workflow" elif (.scripts[] | select(.id == $id)) then "script" elif (.secrets[] | select(.id == $id)) then "secret" else "unknown" end' "$METADATA_DIR/items.json" 2>/dev/null || echo "unknown")
        echo "{\"id\":\"$item\",\"type\":\"$TYPE\",\"risk_level\":\"$RISK\"}"
    done | jq -s .)
    
    jq -n --arg total "$TOTAL_COUNT" --arg critical "$CRITICAL_COUNT" --arg high "$HIGH_COUNT" --raw-output . >/dev/null
    echo "{\"analysis_type\":\"dead_code_detection\",\"summary\":{\"total_unreferenced\":$TOTAL_COUNT,\"critical\":$CRITICAL_COUNT,\"high\":$HIGH_COUNT},\"candidates\":$ITEMS_JSON}"
else
    # Text output
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ DEAD CODE DETECTION REPORT${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ $TOTAL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ No unreferenced items detected${NC}"
        echo "  All items are properly referenced in the dependency graph."
    else
        echo -e "${YELLOW}⚠ Found $TOTAL_COUNT unreferenced items${NC}"
        echo ""
        echo "Items without incoming dependencies:"
        echo ""
        
        while IFS= read -r item; do
            [[ -z "$item" ]] && continue
            
            RISK=$(jq -r --arg id "$item" '((.workflows[] // .scripts[] // .secrets[]) | select(.id == $id) | .risk_level) // "UNKNOWN"' "$METADATA_DIR/items.json" 2>/dev/null || echo "UNKNOWN")
            TYPE=$(jq -r --arg id "$item" 'if (.workflows[] | select(.id == $id)) then "workflow" elif (.scripts[] | select(.id == $id)) then "script" elif (.secrets[] | select(.id == $id)) then "secret" else "unknown" end' "$METADATA_DIR/items.json" 2>/dev/null || echo "unknown")
            
            if [[ "$RISK" == "CRITICAL" ]]; then
                echo -e "  ${RED}✗${NC} $item ($TYPE/$RISK) - CRITICAL: Review before removal"
            elif [[ "$RISK" == "HIGH" ]]; then
                echo -e "  ${YELLOW}!${NC} $item ($TYPE/$RISK) - HIGH: Verify impact"
            else
                echo -e "  ${GREEN}○${NC} $item ($TYPE/$RISK)"
            fi
        done <<< "$UNREFERENCED_LIST"
        
        echo ""
        echo "Recommendations:"
        echo "  - CRITICAL: Must be reviewed by team before removal"
        echo "  - HIGH: Verify dependencies before archival"
        echo "  - Others: Safe to archive if unused externally"
    fi
fi

set -e

