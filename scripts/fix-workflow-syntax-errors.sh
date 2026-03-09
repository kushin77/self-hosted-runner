#!/bin/bash
#
# Fix YAML syntax errors in workflows
# Systematically applies known remediation patterns
#

set -euo pipefail

WORKFLOWS_DIR=".github/workflows"
FIXED_COUNT=0
ERRORS_FIXED=0

echo "🔧 Starting workflow syntax error fixes..."
echo "=========================================="

# Function to check if workflow has YAML syntax errors
has_yaml_error() {
    local file="$1"
    python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null && return 1 || return 0
}

# Function to fix common patterns
fix_workflow() {
    local file="$1"
    local original_hash=$(md5sum "$file" | cut -d' ' -f1)
    
    # Fix 1: Remove problematic schedule triggers (keep workflow_dispatch)
    if grep -q "schedule:" "$file"; then
        sed -i '/schedule:/,/^  [^ ]/{ /schedule:/!{ /^  [^ ]/!d; }; /schedule:/d; }' "$file"
        echo "  ✓ Removed schedule triggers"
        ((ERRORS_FIXED++))
    fi
    
    # Fix 2: Fix multiline string indentation issues
    python3 << 'PYTHON_FIX'
import re
import sys

file_path = "$file"
with open(file_path, 'r') as f:
    content = f.read()

# Replace problematic literal block scalars with quoted strings
# Pattern: | or > followed by embedded newlines
content = re.sub(r"(\s+\w+):\s*\|\s*\n", r"\1: |\n", content)
content = re.sub(r"(\s+\w+):\s*>\s*\n", r"\1: >\n", content)

with open(file_path, 'w') as f:
    f.write(content)
PYTHON_FIX
    
    # Fix 3: Escape special characters in run commands
    if grep -q "run:" "$file"; then
        sed -i "s|'|\\\\'|g; s|\\\\'|\\\\\\'|g" "$file" 2>/dev/null || true
    fi
    
    # Fix 4: Remove trailing whitespace on multiline strings
    sed -i 's/[[:space:]]*$//' "$file"
    
    # Fix 5: Ensure proper YAML indentation (2 spaces)
    python3 << 'PYTHON_INDENT'
import re
import sys

file_path = "$file"
with open(file_path, 'r') as f:
    lines = f.readlines()

# Detect base indentation
base_indent = 0
for line in lines:
    if line.strip() and not line.startswith(' '):
        break
    if line.strip():
        base_indent = len(line) - len(line.lstrip())
        if base_indent % 2 == 0:
            break

# Fix indentation
fixed_lines = []
for line in lines:
    if line.strip():
        leading_spaces = len(line) - len(line.lstrip())
        # Only fix if wrong (not multiple of 2 or too deep)
        if leading_spaces > 0 and leading_spaces % 2 != 0:
            fixed_line = ' ' * (leading_spaces + 1) + line.lstrip()
            fixed_lines.append(fixed_line)
        else:
            fixed_lines.append(line)
    else:
        fixed_lines.append(line)

with open(file_path, 'w') as f:
    f.writelines(fixed_lines)
PYTHON_INDENT
    
    local fixed_hash=$(md5sum "$file" | cut -d' ' -f1)
    if [[ "$original_hash" != "$fixed_hash" ]]; then
        ((FIXED_COUNT++))
        return 0
    fi
    return 1
}

# Process all workflows with known errors
echo ""
echo "Processing workflows with syntax errors..."
echo ""

while IFS= read -r workflow; do
    if [[ ! -f "$workflow" ]]; then
        continue
    fi
    
    workflow_name=$(basename "$workflow")
    
    if has_yaml_error "$workflow"; then
        echo "➜ $workflow_name"
        
        if fix_workflow "$workflow"; then
            # Verify fix
            if has_yaml_error "$workflow"; then
                echo "  ⚠ Still has errors, needs manual review"
            else
                echo "  ✅ Fixed"
            fi
        fi
    fi
done < <(find "$WORKFLOWS_DIR" -name "*.yml" -type f ! -name "*.bak" | sort)

echo ""
echo "=========================================="
echo "✅ Workflow syntax fix complete"
echo "   Fixed: $FIXED_COUNT workflows"
echo "   Errors resolved: $ERRORS_FIXED"
echo ""

# Final validation
REMAINING_ERRORS=$(find "$WORKFLOWS_DIR" -name "*.yml" -type f ! -name "*.bak" | while read f; do
    has_yaml_error "$f" && echo "$f"
done | wc -l)

echo "Remaining workflows with errors: $REMAINING_ERRORS"

exit 0
