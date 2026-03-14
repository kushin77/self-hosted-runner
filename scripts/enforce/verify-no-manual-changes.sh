#!/bin/bash
# ENFORCEMENT: Verify no manual infrastructure changes
# Rule #1: "No direct SSH modifications to infrastructure"

set -euo pipefail

VERBOSE=${VERBOSE:-false}
PROD_TARGET="192.168.168.42"
BACKUP_TARGET="192.168.168.39"

verify_no_manual_changes() {
    local has_errors=0
    
    # Check production target for uncommitted changes
    echo "🔍 Checking production target (${PROD_TARGET}) for manual changes..."
    
    local git_status=$(ssh -i ~/.ssh/id_ed25519 ubuntu@${PROD_TARGET} \
        'cd /home/akushnir/self-hosted-runner && git status --porcelain' 2>/dev/null || echo "error")
    
    if [[ "$git_status" == "error" ]]; then
        echo "❌ Could not reach production target"
        return 1
    fi
    
    if [[ -n "$git_status" ]]; then
        echo "❌ ENFORCEMENT FAILED: Uncommitted changes detected on production:"
        echo "$git_status"
        
        [[ "$VERBOSE" == "true" ]] && {
            echo ""
            echo "Details:"
            ssh -i ~/.ssh/id_ed25519 ubuntu@${PROD_TARGET} \
                'cd /home/akushnir/self-hosted-runner && git diff' | head -50
        }
        
        echo ""
        echo "MANDATE: All infrastructure changes must be:"
        echo "1. Made in git on your development machine"
        echo "2. Committed with clear message"
        echo "3. Pushed to main"
        echo "4. Auto-deployed via Cloud Build"
        echo ""
        echo "Fix:"
        echo "  Option A - Commit changes: git add . && git commit -m '...'; git push"
        echo "  Option B - Revert changes: git checkout HEAD ."
        
        has_errors=1
    else
        echo "✅ No uncommitted changes detected (clean working tree)"
    fi
    
    # Check backup target
    echo ""
    echo "🔍 Checking backup target (${BACKUP_TARGET}) for manual changes..."
    
    local backup_status=$(ssh -i ~/.ssh/id_ed25519 ubuntu@${BACKUP_TARGET} \
        'cd /home/akushnir/self-hosted-runner && git status --porcelain' 2>/dev/null || echo "error")
    
    if [[ "$backup_status" != "error" ]] && [[ -z "$backup_status" ]]; then
        echo "✅ No uncommitted changes on backup target"
    fi
    
    return $has_errors
}

# Run verification
main() {
    echo "════════════════════════════════════════════"
    echo "ENFORCEMENT RULE #1: No Manual Changes"
    echo "════════════════════════════════════════════"
    echo ""
    
    if verify_no_manual_changes; then
        echo ""
        echo "✅ ENFORCEMENT: PASSED"
        echo "Manual infrastructure changes are blocked."
        exit 0
    else
        echo ""
        echo "❌ ENFORCEMENT: FAILED"
        echo "Fix the above issues and try again."
        exit 1
    fi
}

main "$@"
