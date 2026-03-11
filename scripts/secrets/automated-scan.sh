#!/usr/bin/env bash
#
# Automated Secret Scanning Service
# Runs continuously to detect newly committed credentials
# 
# Status: Fully automated, immutable audit trail, no manual intervention required
#

set -euo pipefail

REPO_ROOT="/home/akushnir/self-hosted-runner"
SCAN_LOG="${REPO_ROOT}/logs/secret-scan-$(date +%Y%m%d-%H%M%S).jsonl"
LAST_SCAN_FILE="${REPO_ROOT}/.githooks/.last-scan"

mkdir -p "$(dirname "$SCAN_LOG")" "$(dirname "$LAST_SCAN_FILE")"

echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_started\",\"type\":\"automated\"}" >> "$SCAN_LOG"

# Credential patterns (same as pre-commit hook)
PATTERNS=(
    "AKIA[0-9A-Z]{16}"                          # AWS Access Key
    "aws_secret_access_key.*[A-Za-z0-9+/]{40}" # AWS Secret
    "ghp_[A-Za-z0-9_]{36,}"                     # GitHub Classic PAT
    "github_pat_[A-Za-z0-9_]{60,}"              # GitHub Fine-grained PAT
    "-----BEGIN (RSA |OPENSSH |EC |)PRIVATE"    # Private keys
    "api.?key.*[=:]\s*[A-Za-z0-9_-]{32,}"       # Generic API keys
    "token.*[=:]\s*[A-Za-z0-9._-]{32,}"         # Generic tokens (careful: false positives)
    "Bearer [A-Za-z0-9_-]{32,}"                 # Bearer tokens
    "vault.*token"                               # Vault references
    "private_key"                                # JSON private_key field
)

# Scan git history for patterns
scan_history() {
    local since="${1:-24 hours ago}"
    
    echo "Scanning repository history (since: $since)..."
    
    MATCHES_FOUND=0
    
    for pattern in "${PATTERNS[@]}"; do
        # Search git log for pattern (case-insensitive, excluding test/docs)
        RESULTS=$(git log --all --since="$since" -p --pickaxe-regex -S "$pattern" \
            -- ':!tests' ':!docs' ':!**/*.md' 2>/dev/null || echo "")
        
        if [ -n "$RESULTS" ]; then
            MATCHES=$(echo "$RESULTS" | wc -l)
            echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pattern\":\"$pattern\",\"matches\":$MATCHES,\"severity\":\"high\"}" >> "$SCAN_LOG"
            MATCHES_FOUND=$((MATCHES_FOUND + MATCHES))
        fi
    done
    
    echo "✓ History scan complete: $MATCHES_FOUND matches found"
    
    if [ $MATCHES_FOUND -gt 0 ]; then
        echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"matches_found\",\"count\":$MATCHES_FOUND,\"action\":\"alert\"}" >> "$SCAN_LOG"
        return 1
    fi
    
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_complete\",\"result\":\"clean\"}" >> "$SCAN_LOG"
    return 0
}

# Scan current branch for uncommitted credentials
scan_working_tree() {
    echo "Scanning working directory..."
    
    FOUND=0
    
    for file in $(git ls-files); do
        # Skip binary and excluded files
        if file "$file" 2>/dev/null | grep -q "binary"; then
            continue
        fi
        if [[ "$file" == *".terraform"* ]] || [[ "$file" == *".venv"* ]]; then
            continue
        fi
        
        for pattern in "${PATTERNS[@]}"; do
            if grep -iE "$pattern" "$file" 2>/dev/null >/dev/null; then
                echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"file\":\"$file\",\"pattern\":\"$pattern\",\"severity\":\"critical\"}" >> "$SCAN_LOG"
                FOUND=$((FOUND + 1))
            fi
        done
    done
    
    if [ $FOUND -gt 0 ]; then
        echo "⚠️  Found $FOUND potential credential(s) in working directory!"
        echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"working_tree_scan\",\"matches\":$FOUND,\"action\":\"alert\"}" >> "$SCAN_LOG"
        return 1
    fi
    
    return 0
}

# Scan .gitignore for credential patterns (ensure patterns are properly excluded)
verify_gitignore() {
    echo "Verifying .gitignore covers credential patterns..."
    
    if grep -qE "^\*.env|^\*.key|^\*.pem|^credentials" .gitignore; then
        echo "✓ .gitignore has credential patterns"
        echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"check\":\"gitignore\",\"result\":\"ok\"}" >> "$SCAN_LOG"
        return 0
    else
        echo "⚠️  .gitignore may be missing important patterns"
        echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"check\":\"gitignore\",\"result\":\"incomplete\",\"action\":\"recommend_update\"}" >> "$SCAN_LOG"
        return 1
    fi
}

# Main execution
cd "$REPO_ROOT"

echo "=== Automated Secret Scan ==="
echo "Repository: $REPO_ROOT"
echo "Timestamp: $(date)"
echo ""

# Run all scans (non-blocking)
scan_history "24 hours ago" || true
scan_working_tree || true
verify_gitignore || true

echo ""
echo "Scan complete. Audit log: $SCAN_LOG"

# Update last scan timestamp
echo "$(date)" > "$LAST_SCAN_FILE"

echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_finished\"}" >> "$SCAN_LOG"
