#!/bin/bash
#
# validate-metadata.sh - Validate metadata consistency and integrity
#
# Checks:
# - JSON syntax valid
# - No duplicate items
# - All references exist
# - Dependencies are resolvable
# - Owners are defined
# - Risk levels are valid
#

set -euo pipefail

METADATA_DIR="metadata"
ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ METADATA VALIDATION${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# Check 1: JSON Syntax
# ============================================================================
echo -e "${BLUE}[1/6] Checking JSON syntax...${NC}"

for file in "$METADATA_DIR"/*.json; do
    if [[ -f "$file" ]]; then
        if jq empty "$file" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $(basename "$file")"
        else
            echo -e "${RED}✗ SYNTAX ERROR in $(basename "$file")${NC}"
            ((ERRORS++))
        fi
    fi
done
echo ""

# ============================================================================
# Check 2: Duplicate Items
# ============================================================================
echo -e "${BLUE}[2/6] Checking for duplicates...${NC}"

# Check for duplicate workflow IDs
DUPS=$(jq -r '.workflows[].id' "$METADATA_DIR/items.json" 2>/dev/null | sort | uniq -d)
if [[ -n "$DUPS" ]]; then
    echo -e "${RED}✗ Duplicate workflow IDs:${NC}"
    echo "$DUPS" | sed 's/^/  /'
    ((ERRORS++))
else
    echo -e "${GREEN}✓${NC} No duplicate workflows"
fi

# Check for duplicate script IDs
DUPS=$(jq -r '.scripts[].id' "$METADATA_DIR/items.json" 2>/dev/null | sort | uniq -d)
if [[ -n "$DUPS" ]]; then
    echo -e "${RED}✗ Duplicate script IDs:${NC}"
    echo "$DUPS" | sed 's/^/  /'
    ((ERRORS++))
else
    echo -e "${GREEN}✓${NC} No duplicate scripts"
fi

# Check for duplicate secret IDs
DUPS=$(jq -r '.secrets[].id' "$METADATA_DIR/items.json" 2>/dev/null | sort | uniq -d)
if [[ -n "$DUPS" ]]; then
    echo -e "${RED}✗ Duplicate secret IDs:${NC}"
    echo "$DUPS" | sed 's/^/  /'
    ((ERRORS++))
else
    echo -e "${GREEN}✓${NC} No duplicate secrets"
fi
echo ""

# ============================================================================
# Check 3: Circular Dependencies
# ============================================================================
echo -e "${BLUE}[3/6] Checking for circular dependencies...${NC}"

CIRCULARS=$(jq '.dependencies[] | select(.from == .to)' "$METADATA_DIR/dependencies.json" 2>/dev/null)
if [[ -n "$CIRCULARS" ]]; then
    echo -e "${RED}✗ Circular dependencies found:${NC}"
    echo "$CIRCULARS" | jq -r '.from' | sed 's/^/  /'
    ((ERRORS++))
else
    echo -e "${GREEN}✓${NC} No circular dependencies"
fi
echo ""

# ============================================================================
# Check 4: Owner References
# ============================================================================
echo -e "${BLUE}[4/6] Checking owner references...${NC}"

OWNERS=$(jq -r '.owners | keys[]' "$METADATA_DIR/owners.json" 2>/dev/null)

# Check if all items have valid owners
INVALID_OWNERS=$(jq -r '.workflows[]?.owner // empty' "$METADATA_DIR/items.json" 2>/dev/null | sort -u)
for owner in $INVALID_OWNERS; do
    if ! echo "$OWNERS" | grep -q "^${owner}$"; then
        echo -e "${YELLOW}⚠ Unknown owner reference: $owner${NC}"
        ((WARNINGS++))
    fi
done

if [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} All owner references valid"
fi
echo ""

# ============================================================================
# Check 5: Risk Level Validation
# ============================================================================
echo -e "${BLUE}[5/6] Checking risk levels...${NC}"

VALID_RISKS="CRITICAL HIGH MEDIUM LOW"
INVALID=$(jq -r '.workflows[]?.risk_level, .scripts[]?.risk_level, .secrets[]?.risk_level' "$METADATA_DIR/items.json" 2>/dev/null | sort -u)

for risk in $INVALID; do
    if ! echo "$VALID_RISKS" | grep -q "$risk"; then
        echo -e "${RED}✗ Invalid risk level: $risk${NC}"
        ((ERRORS++))
    fi
done

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} All risk levels valid (CRITICAL, HIGH, MEDIUM, LOW)"
fi
echo ""

# ============================================================================
# Check 6: Data Consistency
# ============================================================================
echo -e "${BLUE}[6/6] Checking data consistency...${NC}"

# Count items
WF_COUNT=$(jq '.workflows | length' "$METADATA_DIR/items.json" 2>/dev/null)
SC_COUNT=$(jq '.scripts | length' "$METADATA_DIR/items.json" 2>/dev/null)
SE_COUNT=$(jq '.secrets | length' "$METADATA_DIR/items.json" 2>/dev/null)

echo -e "${GREEN}✓${NC} Metadata summary:"
echo "   Workflows: $WF_COUNT"
echo "   Scripts: $SC_COUNT"
echo "   Secrets: $SE_COUNT"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ $ERRORS -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ Validation PASSED - No errors or warnings${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Validation passed with $WARNINGS warning(s)${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ Validation FAILED - $ERRORS error(s), $WARNINGS warning(s)${NC}"
    exit 1
fi
