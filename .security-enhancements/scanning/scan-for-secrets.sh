#!/bin/bash
# Comprehensive credential scanning
set -euo pipefail

SCANNING_DIR=".security-enhancements/scanning"
SCAN_REPORT="$SCANNING_DIR/credential-scan-$(date +%Y%m%d_%H%M%S).json"
SECRETS_FOUND=0

echo "Scanning for exposed credentials..."

# Pattern 1: AWS Access Keys
AWS_KEYS=$(grep -r "AKIA[0-9A-Z]\{16\}" . --exclude-dir=.git 2>/dev/null || echo "")
[ -n "$AWS_KEYS" ] && ((SECRETS_FOUND++))

# Pattern 2: GitHub Personal Access Tokens
GH_TOKENS=$(grep -r "ghp_[A-Za-z0-9]\{36,255\}" . --exclude-dir=.git 2>/dev/null || echo "")
[ -n "$GH_TOKENS" ] && ((SECRETS_FOUND++))

# Pattern 3: Private Keys
PRIVATE_KEYS=$(grep -r "-----BEGIN.*PRIVATE KEY" . --exclude-dir=.git 2>/dev/null || echo "")
[ -n "$PRIVATE_KEYS" ] && ((SECRETS_FOUND++))

# Pattern 4: Hardcoded passwords
PASSWORDS=$(grep -r "password\s*=\|passwd\s*=" . --exclude-dir=.git | grep -v ".md:" | grep -v ".yml:" 2>/dev/null || echo "")
[ -n "$PASSWORDS" ] && ((SECRETS_FOUND++))

# Generate report
jq -n \
  --arg timestamp "$(date -Iseconds)" \
  --arg secrets_found "$SECRETS_FOUND" \
  --arg aws_keys "$(echo "$AWS_KEYS" | wc -l)" \
  --arg gh_tokens "$(echo "$GH_TOKENS" | wc -l)" \
  --arg private_keys "$(echo "$PRIVATE_KEYS" | wc -l)" \
  '{
    timestamp: $timestamp,
    scan_type: "comprehensive_credential_scan",
    secrets_found_total: ($secrets_found | tonumber),
    aws_keys: ($aws_keys | tonumber),
    github_tokens: ($gh_tokens | tonumber),
    private_keys: ($private_keys | tonumber),
    status: (if ($secrets_found | tonumber) == 0 then "CLEAN" else "WARNING" end)
  }' > "$SCAN_REPORT"

echo "Scan completed: $([ "$SECRETS_FOUND" -eq 0 ] && echo "✓ CLEAN" || echo "⚠  $SECRETS_FOUND issues found")"
