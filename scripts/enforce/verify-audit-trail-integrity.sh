#!/bin/bash
# ENFORCEMENT: Verify audit trail integrity
# Rule #3: "Immutable audit trail with cryptographic verification"

set -euo pipefail

AUDIT_FILE="logs/credential-audit.jsonl"
SIGNATURE_FILE="${AUDIT_FILE}.signatures"
CHAIN_FILE="${AUDIT_FILE}.chain"
GENESIS_HASH="d62a59e236f5b92e96f30f7234c1798872e35b3e38f4dd59e30f7234c1798872e"

verify_audit_integrity() {
    local line_num=1
    local prev_hash="$GENESIS_HASH"
    
    if [[ ! -f "$AUDIT_FILE" ]]; then
        echo "⚠️  Audit file not found: $AUDIT_FILE"
        return 1
    fi
    
    if [[ ! -f "$SIGNATURE_FILE" ]]; then
        echo "⚠️  Signature file not found: $SIGNATURE_FILE"
        return 1
    fi
    
    echo "🔍 Verifying hash-chain integrity..."
    echo ""
    
    # Count entries
    local entry_count=$(wc -l < "$AUDIT_FILE" 2>/dev/null || echo 0)
    local sig_count=$(wc -l < "$SIGNATURE_FILE" 2>/dev/null || echo 0)
    
    echo "Entries in audit log:    $entry_count"
    echo "Signatures in chain:     $sig_count"
    echo ""
    
    # Verify each entry
    while IFS= read -r entry; do
        local expected_hash=$(sed "${line_num}q;d" "$SIGNATURE_FILE" 2>/dev/null | cut -d' ' -f1)
        
        if [[ -z "$expected_hash" ]]; then
            echo "❌ Line $line_num: Missing signature in $SIGNATURE_FILE"
            return 1
        fi
        
        # Compute SHA256(prev_hash || entry)
        local computed_hash=$(echo -n "${prev_hash}${entry}" | sha256sum | cut -d' ' -f1)
        
        if [[ "$computed_hash" != "$expected_hash" ]]; then
            echo "❌ TAMPERING DETECTED at line $line_num"
            echo "   Expected: $expected_hash"
            echo "   Computed: $computed_hash"
            echo "   Previous: $prev_hash"
            echo "   Entry:    ${entry:0:100}..."
            return 1
        fi
        
        prev_hash="$expected_hash"
        ((line_num++))
    done < "$AUDIT_FILE"
    
    # Verify final hash matches chain file
    local final_hash=$(tail -1 "$CHAIN_FILE" 2>/dev/null || echo "")
    if [[ "$final_hash" != "$prev_hash" ]]; then
        echo "❌ Chain file mismatch:"
        echo "   Chain file has: $final_hash"
        echo "   Should be:      $prev_hash"
        return 1
    fi
    
    echo "✅ All $entry_count entries verified"
    echo "✅ Hash-chain integrity confirmed"
    echo "✅ No tampering detected"
    
    return 0
}

main() {
    echo "════════════════════════════════════════════"
    echo "ENFORCEMENT RULE #3: Audit Trail Integrity"
    echo "════════════════════════════════════════════"
    echo ""
    
    if verify_audit_integrity; then
        echo ""
        echo "✅ ENFORCEMENT: PASSED"
        exit 0
    else
        echo ""
        echo "❌ ENFORCEMENT: FAILED"
        echo ""
        echo "Recovery options:"
        echo "1. Restore from git:      git checkout HEAD -- $AUDIT_FILE*"
        echo "2. Restore from backup:   cp logs/archive/backup-*.jsonl $AUDIT_FILE"
        echo "3. Create incident:       scripts/enforce/create-incident.sh --rule 3"
        exit 1
    fi
}

main "$@"
