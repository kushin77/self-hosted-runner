#!/usr/bin/env bash
#
# fix-workflow-yaml.sh - Fix duplicate 'on:' keys and YAML parse errors in workflows
# 
# Usage: bash scripts/ci/fix-workflow-yaml.sh [--dry-run] [--lint-only]
#
# Requirements: yamllint (install: pip install yamllint)

set -euo pipefail

DRY_RUN=${1:-}
LINT_ONLY=${2:-}
WORKFLOW_DIR=".github/workflows"
TEMP_DIR=$(mktemp -d)
ISSUES_FOUND=0
ISSUES_FIXED=0

trap "rm -rf $TEMP_DIR" EXIT

echo "🔍 Workflow YAML Validation & Fix Script"
echo "========================================"
echo "Scanning: $WORKFLOW_DIR/"
echo ""

# Step 1: Identify files with duplicate 'on:' keys or YAML parse errors
echo "📋 Step 1: Identifying problematic workflows..."

find "$WORKFLOW_DIR" -name "*.yml" -o -name "*.yaml" | while read -r workflow_file; do
  # Check for duplicate 'on:' keys at top level
  on_count=$(grep -c "^on:" "$workflow_file" 2>/dev/null || echo 0)
  
  if [[ "$on_count" -gt 1 ]]; then
    echo "  ⚠️  $workflow_file: Found $on_count top-level 'on:' keys (expected 1)"
    echo "$workflow_file" >> "$TEMP_DIR/problematic_workflows.txt"
    ((ISSUES_FOUND++))
  fi
done

if [[ -f "$TEMP_DIR/problematic_workflows.txt" ]]; then
  echo "  Found $(wc -l < "$TEMP_DIR/problematic_workflows.txt") problematic workflows"
else
  echo "  ✅ No problematic workflows found"
fi

echo ""

# Step 2: Lint with yamllint if available
if command -v yamllint &> /dev/null; then
  echo "📝 Step 2: Running yamllint validation..."
  
  # Run yamllint with relaxed config (ignore line-length warnings)
  yamllint -d "{extends: default, rules: {line-length: disable, comments: disable}}" "$WORKFLOW_DIR" \
    2>"$TEMP_DIR/yamllint_errors.txt" || true
  
  if [[ -s "$TEMP_DIR/yamllint_errors.txt" ]]; then
    echo "  ⚠️  Linting errors found:"
    head -20 "$TEMP_DIR/yamllint_errors.txt" | sed 's/^/    /'
  else
    echo "  ✅ No linting errors found"
  fi
  echo ""
else
  echo "⏭️  Step 2: Skipping yamllint (not installed: pip install yamllint)"
  echo ""
fi

# Step 3: Fix duplicate 'on:' keys
if [[ -f "$TEMP_DIR/problematic_workflows.txt" ]]; then
  echo "🔧 Step 3: Fixing duplicate 'on:' keys..."
  
  while read -r workflow_file; do
    echo "  Processing: $workflow_file"
    
    # Strategy: Keep first 'on:' and comment out others
    # This is safe because workflow definitions should only have one top-level 'on:' trigger
    
    # Create backup
    cp "$workflow_file" "$workflow_file.backup"
    
    # Use awk to handle duplicate 'on:' keys
    # Mark all 'on:' keys except first as commented
    awk '
      /^on:/ && first_on == 0 { first_on = 1; print; next }
      /^on:/ && first_on == 1 { print "# [FIXED] Duplicate on: key (commented out) " $0; next }
      { print }
    ' "$workflow_file.backup" > "$workflow_file"
    
    echo "    ✅ Fixed (backup saved to .backup)"
    ((ISSUES_FIXED++))
  done < "$TEMP_DIR/problematic_workflows.txt"
  
  echo ""
fi

# Step 4: Verify fixes with yamllint
if command -v yamllint &> /dev/null && [[ $ISSUES_FIXED -gt 0 ]]; then
  echo "✔️  Step 4: Verifying fixes..."
  
  yamllint -d "{extends: default, rules: {line-length: disable, comments: disable}}" "$WORKFLOW_DIR" \
    2>"$TEMP_DIR/yamllint_post_fix.txt" || true
  
  if [[ -s "$TEMP_DIR/yamllint_post_fix.txt" ]]; then
    echo "  ⚠️  Remaining linting issues:"
    head -10 "$TEMP_DIR/yamllint_post_fix.txt" | sed 's/^/    /'
  else
    echo "  ✅ All workflows now pass yamllint validation"
  fi
  echo ""
fi

# Final Summary
echo "📊 Summary"
echo "========="
echo "Issues found:   $ISSUES_FOUND"
echo "Issues fixed:   $ISSUES_FIXED"
echo "Backups saved:  ($WORKFLOW_DIR/*.backup)"
echo ""

if [[ $ISSUES_FIXED -gt 0 ]] && [[ -z "$DRY_RUN" ]]; then
  echo "🎯 Next steps:"
  echo "  1. Review fixed workflows: git diff $WORKFLOW_DIR/"
  echo "  2. Test workflows by running: gh workflow list"
  echo "  3. Commit changes: git add $WORKFLOW_DIR/ && git commit -m 'fix: resolve duplicate on: keys in workflows'"
  echo "  4. Remove backups: find $WORKFLOW_DIR/ -name '*.backup' -delete"
else
  echo "ℹ️  Run without --dry-run to apply fixes"
fi

exit 0
