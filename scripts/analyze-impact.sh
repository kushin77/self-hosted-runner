#!/bin/bash
#
# analyze-impact.sh - Impact analysis and blast-radius computation (IDEMPOTENT, NO-OPS)
#
# Computes blast radius of changes to metadata items.
# - Idempotent: reads metadata, outputs analysis (no side effects)
# - No-ops: pure analysis, no mutations
# - Automated: can be called from CI/CD
#
# Usage:
#   ./scripts/analyze-impact.sh <changed-item-id> [--json] [--risk-only]
#
# Examples:
#   ./scripts/analyze-impact.sh aws-credentials
#   ./scripts/analyze-impact.sh deployment --json
#   ./scripts/analyze-impact.sh terraform-apply --risk-only
#

set -euo pipefail

METADATA_DIR="metadata"
CHANGED_ID="${1:-}"
OUTPUT_MODE="${2:-text}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

if [[ -z "$CHANGED_ID" ]]; then
    cat << 'HELP'
analyze-impact.sh - Idempotent impact analysis tool

Usage: analyze-impact.sh <changed-item-id> [--json | --risk-only]

Computes blast radius of changes to metadata items.

Examples:
  ./scripts/analyze-impact.sh aws-credentials
  ./scripts/analyze-impact.sh deployment --json
  ./scripts/analyze-impact.sh terraform-apply --risk-only

Output modes:
  default (text)    - Human-readable report
  --json            - Machine-readable JSON
  --risk-only       - Risk score only (numeric)
HELP
    exit 0
fi

# ============================================================================
# Validation & Data Gathering (read-only, idempotent)
# ============================================================================

# Check if item exists in any collection
ITEM_CHECK=$(jq -r --arg id "$CHANGED_ID" '
    ((.workflows[]? | select(.id == $id) | .id) // 
     (.scripts[]? | select(.id == $id) | .id) // 
     (.secrets[]? | select(.id == $id) | .id)) | 
    if . then "found" else "notfound" end
' "$METADATA_DIR/items.json" 2>/dev/null)

if [[ "$ITEM_CHECK" != "found" ]]; then
    echo -e "${RED}✗ Item not found: $CHANGED_ID${NC}" >&2
    exit 1
fi

# Determine item type and get details
ITEM_TYPE=$(jq -r --arg id "$CHANGED_ID" '
    if (.workflows[] | select(.id == $id) | .id) then "workflow"
    elif (.scripts[] | select(.id == $id) | .id) then "script"  
    elif (.secrets[] | select(.id == $id) | .id) then "secret"
    else "unknown"
    end
' "$METADATA_DIR/items.json" 2>/dev/null | head -1)

ITEM_RISK=$(jq -r --arg id "$CHANGED_ID" '
    (.workflows[] | select(.id == $id) | .risk_level //
     .scripts[] | select(.id == $id) | .risk_level //
     .secrets[] | select(.id == $id) | .risk_level //
     "UNKNOWN") | first
' "$METADATA_DIR/items.json" 2>/dev/null)

ITEM_OWNER=$(jq -r --arg id "$CHANGED_ID" '
    (.workflows[] | select(.id == $id) | .owner //
     .scripts[] | select(.id == $id) | .owner //
     .secrets[] | select(.id == $id) | .owner //
     "unassigned") | first
' "$METADATA_DIR/items.json" 2>/dev/null)

# Find direct dependents (workflows/scripts that depend on this item)
DIRECT_DEPENDENTS=$(jq -r --arg id "$CHANGED_ID" '.dependencies[] | select(.to == $id) | .from' "$METADATA_DIR/dependencies.json" | sort -u)
DIRECT_COUNT=$(echo "$DIRECT_DEPENDENTS" | grep -c . || true)

# Find transitive dependents (second-order effects)
TRANSITIVE_DEPENDENTS=""
for dep in $DIRECT_DEPENDENTS; do
    TRANSITIVE=$(jq -r --arg id "$dep" '.dependencies[] | select(.to == $id) | .from' "$METADATA_DIR/dependencies.json" | sort -u)
    [[ -n "$TRANSITIVE" ]] && TRANSITIVE_DEPENDENTS="$TRANSITIVE_DEPENDENTS${TRANSITIVE}
"
done
TRANSITIVE_DEPENDENTS=$(echo "$TRANSITIVE_DEPENDENTS" | sort -u | sed '/^$/d')
TRANSITIVE_COUNT=$(echo "$TRANSITIVE_DEPENDENTS" | grep -c . || true)

# Find items this depends on (to understand cascading failures)
DEPENDENCIES=$(jq -r --arg id "$CHANGED_ID" '.dependencies[] | select(.from == $id) | .to' "$METADATA_DIR/dependencies.json" | sort -u)
DEP_COUNT=$(echo "$DEPENDENCIES" | grep -c . || true)

# ============================================================================
# Risk Scoring (idempotent formula)
# ============================================================================

RISK_BASE=0
case "$ITEM_RISK" in
    CRITICAL) RISK_BASE=40 ;;
    HIGH) RISK_BASE=25 ;;
    MEDIUM) RISK_BASE=15 ;;
    LOW) RISK_BASE=5 ;;
    *) RISK_BASE=10 ;;
esac

# Impact multiplier based on dependents
RISK_IMPACT=$((DIRECT_COUNT * 10 + TRANSITIVE_COUNT * 3))
RISK_SCORE=$((RISK_BASE + RISK_IMPACT))
[[ $RISK_SCORE -gt 100 ]] && RISK_SCORE=100

# Severity classification (immutable logic)
if [[ $RISK_SCORE -ge 75 ]]; then
    SEVERITY="CRITICAL"
elif [[ $RISK_SCORE -ge 50 ]]; then
    SEVERITY="HIGH"
elif [[ $RISK_SCORE -ge 25 ]]; then
    SEVERITY="MEDIUM"
else
    SEVERITY="LOW"
fi

# ============================================================================
# Output Generation (idempotent, no mutations)
# ============================================================================

if [[ "$OUTPUT_MODE" == "--json" ]]; then
    # Machine-readable JSON
    jq -n \
        --arg id "$CHANGED_ID" \
        --arg type "$ITEM_TYPE" \
        --arg risk "$ITEM_RISK" \
        --arg owner "$ITEM_OWNER" \
        --argjson direct_count "$DIRECT_COUNT" \
        --argjson transitive_count "$TRANSITIVE_COUNT" \
        --argjson dependency_count "$DEP_COUNT" \
        --argjson risk_score "$RISK_SCORE" \
        --arg severity "$SEVERITY" \
        --arg direct_deps "$DIRECT_DEPENDENTS" \
        --arg transitive_deps "$TRANSITIVE_DEPENDENTS" \
        --arg dependencies "$DEPENDENCIES" \
        '{
            item: {
                id: $id,
                type: $type,
                risk_level: $risk,
                owner: $owner
            },
            blast_radius: {
                direct_affected: $direct_count,
                transitive_affected: $transitive_count,
                total_affected: ($direct_count + $transitive_count),
                dependencies: $dependency_count
            },
            risk_assessment: {
                score: $risk_score,
                severity: $severity,
                formula: "base(risk_level) + (direct_dependents × 10) + (transitive_dependents × 3)"
            },
            affected_items: {
                direct: ($direct_deps | split("\n") | map(select(length > 0))),
                transitive: ($transitive_deps | split("\n") | map(select(length > 0)))
            },
            dependencies: ($dependencies | split("\n") | map(select(length > 0)))
        }'
elif [[ "$OUTPUT_MODE" == "--risk-only" ]]; then
    # Just the score (for automated CI gates)
    echo "$RISK_SCORE"
else
    # Human-readable text output
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ IMPACT ANALYSIS${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${MAGENTA}Changed Item:${NC}"
    echo "  ID:           $CHANGED_ID"
    echo "  Type:         $ITEM_TYPE"
    echo "  Risk Level:   $ITEM_RISK"
    echo "  Owner:        $ITEM_OWNER"
    echo ""
    echo -e "${MAGENTA}Blast Radius:${NC}"
    echo "  Direct Affects:      $DIRECT_COUNT items"
    echo "  Transitive Affects:  $TRANSITIVE_COUNT items"
    echo "  Total Affected:      $((DIRECT_COUNT + TRANSITIVE_COUNT)) items"
    echo "  Dependencies On:     $DEP_COUNT items"
    echo ""
    
    if [[ $DIRECT_COUNT -gt 0 ]]; then
        echo -e "${MAGENTA}Directly Affected (depend on $CHANGED_ID):${NC}"
        echo "$DIRECT_DEPENDENTS" | sed 's/^/  • /'
        echo ""
    fi
    
    if [[ $TRANSITIVE_COUNT -gt 0 ]]; then
        echo -e "${MAGENTA}Transitively Affected (depend on above):${NC}"
        echo "$TRANSITIVE_DEPENDENTS" | sed 's/^/  • /'
        echo ""
    fi
    
    if [[ $DEP_COUNT -gt 0 ]]; then
        echo -e "${MAGENTA}Dependencies (this item depends on):${NC}"
        echo "$DEPENDENCIES" | sed 's/^/  • /'
        echo ""
    fi
    
    echo -e "${MAGENTA}Risk Assessment:${NC}"
    if [[ "$SEVERITY" == "CRITICAL" ]]; then
        echo -e "  Severity:       ${RED}CRITICAL${NC}"
    elif [[ "$SEVERITY" == "HIGH" ]]; then
        echo -e "  Severity:       ${YELLOW}HIGH${NC}"
    elif [[ "$SEVERITY" == "MEDIUM" ]]; then
        echo -e "  Severity:       ${YELLOW}MEDIUM${NC}"
    else
        echo -e "  Severity:       ${GREEN}LOW${NC}"
    fi
    echo "  Risk Score:     $RISK_SCORE / 100"
    echo "  Formula:        base($ITEM_RISK=$RISK_BASE) + impacts"
    echo ""
    
    if [[ $((DIRECT_COUNT + TRANSITIVE_COUNT)) -gt 0 ]]; then
        echo -e "${YELLOW}⚠  WARNING: Changes to this item affect $((DIRECT_COUNT + TRANSITIVE_COUNT)) dependent items${NC}"
        echo "  - Perform regression testing on affected workflows"
        echo "  - Review security implications with $ITEM_OWNER"
        echo "  - Consider staged rollout for CRITICAL items"
    else
        echo -e "${GREEN}✓ Safe: No dependent items detected${NC}"
    fi
fi
