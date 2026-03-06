#!/usr/bin/env bash
# Security Audit: Sanitize repository for token-like placeholders
# Purpose: Find and redact token-like literals from docs/artifacts
# Status: Automated via .github/workflows/security-audit.yml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
REPORT_FILE="${PROJECT_ROOT}/security-sanitization-report.md"

# Patterns to search for (with safe keywords excluded)
declare -A UNSAFE_PATTERNS=(
    ["vault_token"]="s\.[a-zA-Z0-9]{20,}"
    ["github_token"]="ghp_[a-zA-Z0-9]{36,}"
    ["aws_access_key"]="AKIA[0-9A-Z]{16}"
    ["generic_secret"]='password\s*[:=]\s*["\']?[a-zA-Z0-9!@#$%^&*()]{8,}["\']?'
)

# Safe keywords (indicates example/placeholder)
SAFE_KEYWORDS=(
    "example"
    "placeholder"
    "YOUR_"
    "your_"
    "<token>"
    "<secret>"
    "REDACTED"
    "SANITIZED"
)

echo "🔒 Repository Security Sanitization Audit"
echo "=========================================="
echo ""

FINDINGS=()
TOTAL_FILES=0
UNSAFE_FILES=0

# Scan all markdown and YAML files in docs/scripts
for file in $(find "${PROJECT_ROOT}" -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" -o -name "*.sh" \) ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.terraform/*'); do
    ((TOTAL_FILES++))
    
    for pattern_name in "${!UNSAFE_PATTERNS[@]}"; do
        pattern="${UNSAFE_PATTERNS[$pattern_name]}"
        
        # Check if pattern exists in file
        if grep -E "$pattern" "$file" > /dev/null 2>&1; then
            # Check if it's in a safe context
            LINE_NUM=$(grep -n -E "$pattern" "$file" | head -1 | cut -d: -f1)
            CONTEXT=$(sed -n "${LINE_NUM}p" "$file")
            
            # Verify it's not a safe example
            IS_SAFE=false
            for keyword in "${SAFE_KEYWORDS[@]}"; do
                if [[ "$CONTEXT" == *"$keyword"* ]]; then
                    IS_SAFE=true
                    break
                fi
            done
            
            if [ "$IS_SAFE" = false ]; then
                echo "⚠️  UNSAFE FINDING: $file:$LINE_NUM ($pattern_name)"
                echo "   Context: $(echo "$CONTEXT" | head -c 80)..."
                FINDINGS+=("$file:$LINE_NUM:$pattern_name")
                ((UNSAFE_FILES++))
            fi
        fi
    done
done

echo ""
echo "📊 Scan Results:"
echo "================"
echo "Total files scanned: $TOTAL_FILES"
echo "Files with unsafe findings: $UNSAFE_FILES"
echo ""

# Generate report
cat > "$REPORT_FILE" << EOF
# Security Sanitization Report

**Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Status**: $([ $UNSAFE_FILES -eq 0 ] && echo "✅ PASS" || echo "⚠️ FINDINGS")

## Summary
- Total files scanned: $TOTAL_FILES
- Unsafe findings: $UNSAFE_FILES

## Recommendations

### For Developers
1. **Never commit real secrets** - Use GitHub Secrets instead
2. **Use safe placeholders** - Mark examples with `example`, `placeholder`, or `YOUR_` prefix
3. **Pre-commit hooks** - Run \`security-audit.yml\` workflow on PRs

### For Maintainers
1. **Review PRs** - Check for any token-like patterns before merge
2. **Rotate secrets** - If any real secrets are found, rotate them immediately
3. **Audit logs** - Review git history for any accidentally committed secrets

## Safe Practices
✅ Use environment variables for secrets  
✅ Store credentials in GitHub Secrets  
✅ Mark examples with safe keywords (YOUR_, example, placeholder, <token>)  
✅ Use REDACTED or SANITIZED for documentation  
✅ Enable branch protection + require security audit pass  

## Files to Review
$(if [ $UNSAFE_FILES -gt 0 ]; then
    echo "The following files were flagged (likely safe examples):"
    for finding in "${FINDINGS[@]}"; do
        echo "- $finding"
    done
else
    echo "✅ No unsafe findings detected"
fi)

---

**Automated by**: \`.github/workflows/security-audit.yml\`  
**Next run**: On next PR or push to main
EOF

echo ""
echo "✅ Report written to: $REPORT_FILE"

if [ $UNSAFE_FILES -eq 0 ]; then
    echo "✅ Security audit passed - no unsafe secrets found"
    exit 0
else
    echo "⚠️  Review findings above and sanitize if needed"
    exit 1
fi
