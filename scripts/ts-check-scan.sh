#!/bin/bash
# ts-check-scan.sh - Scan repository for TypeScript configuration and type-check status
# Output: Report listing all packages with TypeScript and their check status

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_FILE="${REPO_ROOT}/TS_CHECK_REPORT.md"

echo "🔍 Scanning repository for TypeScript usage..."

# Initialize report
cat > "${REPORT_FILE}" <<'EOF'
# Repository-Wide TypeScript Status Report

Generated: $(date)

## Summary
This report identifies all packages with TypeScript configuration and their type-check status.

## Packages

EOF

TOTAL=0
PASSING=0
FAILING=0

# Find all tsconfig.json files
while IFS= read -r TSCONFIG; do
    if [[ -z "$TSCONFIG" ]]; then
        continue
    fi
    
    PACKAGE_DIR="$(dirname "$TSCONFIG")"
    PACKAGE_NAME="${PACKAGE_DIR#$REPO_ROOT/}"
    RELATIVE_PACKAGE="${PACKAGE_DIR#$REPO_ROOT/}"
    
    echo ""
    echo "Checking: $RELATIVE_PACKAGE"
    
    TOTAL=$((TOTAL + 1))
    
    # Check if package.json exists and has a type-check script
    PACKAGE_JSON="${PACKAGE_DIR}/package.json"
    
    if [[ ! -f "$PACKAGE_JSON" ]]; then
        echo "  ⚠️  No package.json found - skipping type-check"
        cat >> "${REPORT_FILE}" <<EOF

### ${RELATIVE_PACKAGE}
- **Status**: ⚠️ No package.json
- **Type-Check Script**: Not applicable

EOF
        continue
    fi
    
    # Run type-check if possible
    if grep -q "type-check" "$PACKAGE_JSON"; then
        cd "$PACKAGE_DIR"
        if npm run type-check --silent 2>&1 > /tmp/ts_check_output.txt; then
            echo "  ✅ Type-check PASSED"
            PASSING=$((PASSING + 1))
            STATUS="✅ PASSED"
            ERROR_COUNT="0"
        else
            echo "  ❌ Type-check FAILED"
            FAILING=$((FAILING + 1))
            STATUS="❌ FAILED"
            # Count errors in output
            ERROR_COUNT=$(grep -c "error TS" /tmp/ts_check_output.txt || echo "unknown")
        fi
        cd "$REPO_ROOT"
        
        cat >> "${REPORT_FILE}" <<EOF

### ${RELATIVE_PACKAGE}
- **Status**: ${STATUS}
- **Errors**: ${ERROR_COUNT}
- **Type-Check Script**: \`npm run type-check\`

EOF
    else
        # Try running tsc directly if it's available
        if [[ -f "${PACKAGE_DIR}/node_modules/.bin/tsc" ]]; then
            echo "  ℹ️  Running tsc directly..."
            cd "$PACKAGE_DIR"
            if ./node_modules/.bin/tsc --noEmit 2>&1 > /tmp/ts_check_output.txt; then
                echo "  ✅ Type-check PASSED"
                PASSING=$((PASSING + 1))
                STATUS="✅ PASSED (manual tsc)"
                ERROR_COUNT="0"
            else
                echo "  ❌ Type-check FAILED"
                FAILING=$((FAILING + 1))
                STATUS="❌ FAILED (manual tsc)"
                ERROR_COUNT=$(grep -c "error TS" /tmp/ts_check_output.txt || echo "unknown")
            fi
            cd "$REPO_ROOT"
            
            cat >> "${REPORT_FILE}" <<EOF

### ${RELATIVE_PACKAGE}
- **Status**: ${STATUS}
- **Errors**: ${ERROR_COUNT}
- **Type-Check Script**: Manual \`tsc --noEmit\`

EOF
        else
            echo "  ⚠️  No type-check script or tsc found"
            cat >> "${REPORT_FILE}" <<EOF

### ${RELATIVE_PACKAGE}
- **Status**: ⚠️ No type-check available
- **Type-Check Script**: None found

EOF
        fi
    fi
done < <(find "$REPO_ROOT" -name "tsconfig.json" -type f | grep -v node_modules | sort)

# Summary
echo ""
echo "📊 Summary:"
echo "  Total: $TOTAL"
echo "  Passing: $PASSING"
echo "  Failing: $FAILING"

# Append summary to report
cat >> "${REPORT_FILE}" <<EOF

## Summary

| Metric | Count |
|--------|-------|
| **Total Packages** | ${TOTAL} |
| **Passing Checks** | ${PASSING} |
| **Failing Checks** | ${FAILING} |

## Next Steps

1. For each failing package, create a follow-up issue with prioritized fixes
2. Set up CI job to run \`ts-check-scan.sh\` on each PR to enforce compliance
3. Progressively tighten TypeScript compiler flags per package (see Issue #75 as example)

---

*Report generated: $(date)*
EOF

echo "✅ Report generated: ${REPORT_FILE}"
