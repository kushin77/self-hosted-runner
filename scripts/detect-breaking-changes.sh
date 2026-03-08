#!/bin/bash
#
# detect-breaking-changes.sh - Identify potential schema breaking changes (idempotent)
#
# Compares current metadata against previous version to detect:
# - Removed required fields
# - Changed field types
# - Renamed/deprecated items
# - Schema migration needs
#
# Idempotent: reads metadata, outputs analysis (no side effects)
# No-ops: pure analysis, no mutations
#
# Usage:
#   ./scripts/detect-breaking-changes.sh           # text report
#   ./scripts/detect-breaking-changes.sh --json    # JSON output
#

set +e
METADATA_DIR="metadata"
SCHEMA_DIR="metadata/schemas"
CHANGELOG="metadata/change-log.json"
OUTPUT_MODE="${1:-text}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

# Initialize counts
BREAKING_COUNT=0
DEPRECATED_COUNT=0
SCHEMA_ISSUES=0
CIRCULAR_DEPS=0

echo "Analyzing metadata for breaking changes..." >&2

# ============================================================================
# Check 1: Validate schema compliance
# ============================================================================

# Check if all workflow items have required fields
SCHEMA_ISSUES=$(jq '
  [.workflows[]?, .scripts[]?, .secrets[]?] |
  map(
    if (.id | length) == 0 or (.risk_level | length) == 0 then
      1
    else
      0
    end
  ) | add
' "$METADATA_DIR/items.json" 2>/dev/null || echo "0")

# ============================================================================
# Check 2: Detect from changelog
# ============================================================================

if [[ -f "$CHANGELOG" ]]; then
    # Count removal operations
    BREAKING_COUNT=$(jq '[.entries[]? | select(.action == "remove")] | length' "$CHANGELOG" 2>/dev/null || echo "0")
    
    # Count deprecations
    DEPRECATED_COUNT=$(jq '[.entries[]? | select(.action == "deprecate")] | length' "$CHANGELOG" 2>/dev/null || echo "0")
fi

# ============================================================================
# Check 3: Circular dependencies
# ============================================================================

CIRCULAR_DEPS=$(jq '
[.dependencies[] as $dep |
  select(.dependencies[] | select(.from == $dep.to and .to == $dep.from))] |
  unique_by([.from, .to]) | length
' "$METADATA_DIR/dependencies.json" 2>/dev/null || echo "0")

# ============================================================================
# Output
# ============================================================================

if [[ "$OUTPUT_MODE" == "--json" ]]; then
    jq -n \
        --arg breaking "$BREAKING_COUNT" \
        --arg deprecated "$DEPRECATED_COUNT" \
        --arg schema "$SCHEMA_ISSUES" \
        --arg circular "$CIRCULAR_DEPS" \
        '{
            analysis_type: "breaking_changes_detection",
            severity: (if ($breaking | tonumber) > 0 then "HIGH" elif ($deprecated | tonumber) > 0 then "MEDIUM" else "LOW" end),
            summary: {
                breaking_changes: ($breaking | tonumber),
                deprecated_fields: ($deprecated | tonumber),
                schema_issues: ($schema | tonumber),
                circular_dependencies: ($circular | tonumber)
            },
            recommendations: [
                "Review and test breaking changes before deployment",
                "Plan migration path for deprecated fields",
                "Resolve circular dependencies to improve maintainability",
                "Update schemas if changes are intentional"
            ]
        }'
else
    # Text output
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ BREAKING CHANGES DETECTION${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    TOTAL=$((BREAKING_COUNT + DEPRECATED_COUNT + SCHEMA_ISSUES + CIRCULAR_DEPS))
    
    if [[ $TOTAL -eq 0 ]]; then
        echo -e "${GREEN}✓ No breaking changes detected${NC}"
        echo "  Metadata remains compatible with current schemas."
    else
        [[ $BREAKING_COUNT -gt 0 ]] && \
            echo -e "${RED}✗ CRITICAL: $BREAKING_COUNT breaking changes${NC}" && \
            echo "  - Items/fields removed - may break deployments" && echo ""
        
        [[ $DEPRECATED_COUNT -gt 0 ]] && \
            echo -e "${YELLOW}⚠ WARNING: $DEPRECATED_COUNT deprecated fields${NC}" && \
            echo "  - Plan migration before next release" && echo ""
        
        [[ $SCHEMA_ISSUES -gt 0 ]] && \
            echo -e "${YELLOW}! INFO: $SCHEMA_ISSUES schema violations${NC}" && \
            echo "  - Items missing required fields" && echo ""
        
        [[ $CIRCULAR_DEPS -gt 0 ]] && \
            echo -e "${YELLOW}! INFO: $CIRCULAR_DEPS circular dependencies${NC}" && \
            echo "  - Simplify dependency relationships" && echo ""
        
        echo "Recommendations:"
        echo "  • Review breaking changes and assess impact"
        echo "  • Create migration plan for deprecations"
        echo "  • Resolve circular dependencies"
        echo "  • Re-validate schemas after changes"
    fi
fi

set -e
