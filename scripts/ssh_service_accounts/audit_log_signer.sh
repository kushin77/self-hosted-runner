#!/bin/bash
# Audit Log Hash-Chain Signer
# Signs each JSONL entry with SHA-256 hash-chain for immutable verification
# Enables detection of tampering or unauthorized deletion
# Usage: audit_log_signer.sh {sign|verify|status}

set -euo pipefail

readonly AUDIT_LOG="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/logs/credential-audit.jsonl}"
readonly SIGNATURE_FILE="${AUDIT_LOG}.signatures"
readonly HASH_CHAIN_FILE="${AUDIT_LOG}.chain"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }

# Initialize or verify hash chain file exists
init_or_verify_chain() {
    if [ ! -f "$HASH_CHAIN_FILE" ]; then
        # First run: initialize with SHA-256 of "GENESIS"
        echo "d62a59236f5b92e96f30f7234c1798872e35b3e38f4dd59e30f7234c1798872e" > "$HASH_CHAIN_FILE"
        log_success "Initialized hash chain"
        return 0
    fi
}

# Sign all unprocessed entries
sign_unprocessed_entries() {
    local last_signed_line=0
    
    if [ -f "$SIGNATURE_FILE" ]; then
        last_signed_line=$(tail -1 "$SIGNATURE_FILE" 2>/dev/null | awk '{print $1}' || echo 0)
    fi
    
    [ ! -f "$AUDIT_LOG" ] && {
        log_error "Audit log not found: $AUDIT_LOG"
        return 1
    }
    
    local current_line=0
    local prev_hash=$(cat "$HASH_CHAIN_FILE")
    local signed_count=0
    
    while IFS= read -r entry; do
        ((current_line++))
        
        if [ $current_line -le $last_signed_line ]; then
            continue
        fi
        
        # Hash = SHA256(previous_hash || entry)
        # Using || (concatenation) for chain linking
        local combined="${prev_hash}${entry}"
        local entry_hash=$(echo -n "$combined" | sha256sum | awk '{print $1}')
        
        # Store signature: line_number hash timestamp
        echo "$current_line $entry_hash $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SIGNATURE_FILE"
        
        prev_hash="$entry_hash"
        ((signed_count++))
    done < "$AUDIT_LOG"
    
    # Update chain file with latest hash for next sign cycle
    echo "$prev_hash" > "$HASH_CHAIN_FILE"
    
    if [ $signed_count -gt 0 ]; then
        log_success "Signed $signed_count new audit entries (hash-chain updated)"
    else
        log_info "No new entries to sign"
    fi
}

# Verify integrity of entire audit trail
verify_integrity() {
    log_info "Verifying audit trail integrity with hash-chain..."
    
    if [ ! -f "$SIGNATURE_FILE" ]; then
        log_error "No signatures found. Run 'audit_log_signer.sh init' first"
        return 1
    fi
    
    if [ ! -f "$AUDIT_LOG" ]; then
        log_error "Audit log not found: $AUDIT_LOG"
        return 1
    fi
    
    local expected_hash="d62a59236f5b92e96f30f7234c1798872e35b3e38f4dd59e30f7234c1798872e"  # GENESIS
    local errors=0
    local verified=0
    
    while IFS=' ' read -r line_num expected_from_sig timestamp; do
        local entry=$(sed -n "${line_num}p" "$AUDIT_LOG" 2>/dev/null || echo "")
        
        if [ -z "$entry" ]; then
            log_error "Missing entry at line $line_num (tampering detected)"
            ((errors++))
            continue
        fi
        
        # Recompute hash
        local combined="${expected_hash}${entry}"
        local computed_hash=$(echo -n "$combined" | sha256sum | awk '{print $1}')
        
        if [ "$computed_hash" != "$expected_from_sig" ]; then
            log_error "Hash mismatch at line $line_num - possible tampering"
            echo "  Expected: $expected_from_sig"
            echo "  Computed: $computed_hash"
            ((errors++))
        else
            ((verified++))
        fi
        
        expected_hash="$computed_hash"
    done < "$SIGNATURE_FILE"
    
    echo ""
    log_info "Verification complete: $verified verified, $errors errors"
    
    if [ $errors -eq 0 ]; then
        log_success "Audit trail integrity VERIFIED - No tampering detected"
        return 0
    else
        log_error "Integrity verification FAILED - $errors anomalies detected"
        return 1
    fi
}

# Show signature status and latest hash
show_status() {
    echo "═══════════════════════════════════════════════════════════"
    echo "AUDIT LOG SIGNER STATUS"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Audit Log: $AUDIT_LOG"
    echo "   Entries: $(wc -l < "$AUDIT_LOG" || echo 0)"
    echo ""
    echo "Signatures: $SIGNATURE_FILE"
    echo "   Signed:   $(wc -l < "$SIGNATURE_FILE" || echo 0)"
    echo ""
    echo "Hash Chain: $HASH_CHAIN_FILE"
    echo "   Current:  $(cat "$HASH_CHAIN_FILE" 2>/dev/null || echo "NOT INITIALIZED")"
    echo ""
}

main() {
    mkdir -p "$(dirname "$SIGNATURE_FILE")"
    mkdir -p "$(dirname "$HASH_CHAIN_FILE")"
    
    case "${2:-verify}" in
        init)
            init_or_verify_chain
            ;;
        sign)
            init_or_verify_chain
            sign_unprocessed_entries
            ;;
        verify)
            verify_integrity
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 [audit_log_path] {init|sign|verify|status}"
            echo ""
            echo "Commands:"
            echo "  init     - Initialize hash-chain (first run only)"
            echo "  sign     - Sign unprocessed audit entries with SHA-256"
            echo "  verify   - Verify audit trail integrity (detect tampering)"
            echo "  status   - Show current signer status"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
