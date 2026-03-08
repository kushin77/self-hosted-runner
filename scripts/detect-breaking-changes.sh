#!/bin/bash
#
# detect-breaking-changes.sh - Detect what breaks when you change an item
#
# Usage:
#   bash scripts/detect-breaking-changes.sh --item terraform-apply.yml --change "rename to terraform-plan-and-apply.yml"
#   bash scripts/detect-breaking-changes.sh --secret AWS_OIDC_ROLE_ARN --change "delete"
#   bash scripts/detect-breaking-changes.sh --script deploy.sh --change "change function signature"
#

set -euo pipefail

ITEM_NAME=""
CHANGE_DESCRIPTION=""
METADATA_DIR="metadata"

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
        --item)
            ITEM_NAME="$2"
            shift 2
            ;;
        --change)
            CHANGE_DESCRIPTION="$2"
            shift 2
            ;;
        --secret)
            ITEM_NAME="$2"
            shift 2
            ;;
        --script)
            ITEM_NAME="$2"
            shift 2
            ;;
        --workflow)
            ITEM_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$ITEM_NAME" ]]; then
    echo "Error: Must specify --item name"
    exit 1
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

search_in_files() {
    local pattern=$1
    local search_dirs="${2:-.github/workflows scripts metadata}"
    
    grep -r "$pattern" $search_dirs 2>/dev/null | grep -v "\.git" | head -20 || echo ""
}

get_item_type() {
    local name=$1
    
    if [[ "$name" == *".yml" ]] || [[ "$name" == *".yaml" ]]; then
        echo "workflow"
    elif grep -q "^[A-Z_]*$" <<< "$name"; then
        echo "secret"
    else
        echo "script"
    fi
}

# ============================================================================
# MAIN ANALYSIS
# ============================================================================

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║ BREAKING CHANGE DETECTION${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

ITEM_TYPE=$(get_item_type "$ITEM_NAME")

echo -e "${BLUE}📋 Item Analysis${NC}"
echo "   Name: $ITEM_NAME"
echo "   Type: $ITEM_TYPE"
echo "   Change: $CHANGE_DESCRIPTION"
echo ""

# Search for references
echo -e "${YELLOW}⚠️  Breaking Changes Detected:${NC}"
echo ""

# Find all references to the item
REFERENCES=$(search_in_files "$ITEM_NAME")
REFERENCE_COUNT=$(echo "$REFERENCES" | grep -c . || echo 0)

if [[ $REFERENCE_COUNT -gt 0 ]]; then
    echo -e "${RED}❌ WILL BREAK (requires changes):${NC}"
    echo "$REFERENCES" | while IFS=: read -r file content; do
        echo ""
        echo "   📄 $file"
        echo "      Current: $content" | head -c 70
        echo ""
        
        # Determine what needs to change
        if [[ "$CHANGE_DESCRIPTION" == *"rename"* ]]; then
            OLD_NAME=$(echo "$CHANGE_DESCRIPTION" | sed 's/.*rename to //')
            echo "      Must update: reference new name ($OLD_NAME)"
        elif [[ "$CHANGE_DESCRIPTION" == *"delete"* ]]; then
            echo "      ❌ CRITICAL: This item must be removed/updated"
        elif [[ "$CHANGE_DESCRIPTION" == *"change"* ]]; then
            echo "      ⚠️  May need updates depending on compatibility"
        fi
    done | head -30
    
    echo ""
    echo -e "${RED}Files affected: $REFERENCE_COUNT${NC}"
else
    echo -e "${GREEN}✓ No breaking changes detected${NC}"
fi

# Impact summary
echo ""
echo -e "${BLUE}📊 Impact Summary${NC}"

case "$ITEM_TYPE" in
    workflow)
        echo "   Will impact:"
        echo "   • Dependent workflows (those that call this)"
        echo "   • CI/CD pipelines (those that depend on this)"
        echo "   • Error codes (documentation references)"
        echo "   • WORKFLOWS_INDEX.md (index entry)"
        ;;
    script)
        echo "   Will impact:"
        echo "   • Workflows that call this script"
        echo "   • Other scripts that depend on this"
        echo "   • SCRIPTS_REGISTRY.md (index entry)"
        echo "   • Documentation references"
        ;;
    secret)
        echo "   Will impact:"
        echo "   • All workflows using this secret"
        echo "   • All scripts accessing this secret"
        echo "   • SECRETS_INDEX.md (catalog entry)"
        echo "   • Environment configuration"
        ;;
esac

# Recommendations
echo ""
echo -e "${PURPLE}💡 Recommendations:${NC}"

if [[ "$REFERENCE_COUNT" -gt 0 ]]; then
    echo -e "   ${RED}This change has breaking impacts${NC}"
    echo ""
    if [[ "$CHANGE_DESCRIPTION" == *"rename"* ]]; then
        echo "   ✓ Use safe refactoring:"
        echo "      bash scripts/refactor-item.sh --old-name \"$ITEM_NAME\" --new-name \"NEW_NAME\""
        echo ""
        echo "   Or migrate safely:"
        echo "      1. Keep old item as deprecated"
        echo "      2. Create new item with new name"
        echo "      3. Gradually migrate references"
        echo "      4. Remove old item after 2-3 releases"
    elif [[ "$CHANGE_DESCRIPTION" == *"delete"* ]]; then
        echo "   ✓ Before deletion:"
        echo "      1. Find all references: grep -r \"$ITEM_NAME\" ."
        echo "      2. Migrate those references"
        echo "      3. Update documentation"
        echo "      4. Update metadata/items.json"
        echo "      5. Add entry to CHANGELOG.md"
    else
        echo "   ✓ Before making this change:"
        echo "      1. Update all affected files"
        echo "      2. Test thoroughly in staging"
        echo "      3. Notify affected teams"
        echo "      4. Create CHANGELOG entry"
        echo "      5. Include migration guide in PR"
    fi
else
    echo "   ✓ This change appears safe to make"
    echo "   • Before merging: Run full test suite"
    echo "   • Document change in commit message"
    echo "   • Update CHANGELOG.md"
fi

echo ""
echo -e "${BLUE}🔄 Safe Refactoring Process:${NC}"
echo ""
echo "   1. Create feature branch: git checkout -b refactor/$ITEM_NAME"
echo "   2. Make change to item"
echo "   3. Update all references"
echo "   4. Update metadata/items.json"
echo "   5. Update indices"
echo "   6. Test: bash scripts/validate-metadata.sh"
echo "   7. Create PR with detailed description"
echo "   8. Notify owner and affected teams"
echo "   9. Require +2 approvals for CRITICAL changes"
echo "   10. Merge and monitor"
echo ""

echo -e "${GREEN}Analysis complete${NC}"
echo ""
