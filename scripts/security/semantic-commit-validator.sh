#!/bin/bash

################################################################################
# Semantic Commit Validator - Policy-Driven Commit Enforcement
# Validates commit messages + metadata against governance rules
# Blocks commits violating: naming, credentialsrefs, policy metadata
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT_LOG="${PROJECT_ROOT}/logs/governance/semantic-commits.jsonl"

mkdir -p "$(dirname "$AUDIT_LOG")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }

audit_log() {
    local rule="$1" status="$2" commit="$3" reason="${4:-}"
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"rule\":\"$rule\",\"status\":\"$status\",\"commit\":\"$commit\",\"reason\":\"$reason\"}" >> "$AUDIT_LOG"
}

################################################################################
# VALIDATION RULES
################################################################################

# Rule 1: Commit Message Format
validate_commit_format() {
    local msg="$1"
    
    # Pattern: ^(feat|fix|docs|test|refactor|chore|style)(\.cred)?(\(.+\))?: .+
    if [[ ! "$msg" =~ ^(feat|fix|docs|test|refactor|chore|style)(\(.+\))?:\ [A-Za-z] ]]; then
        error "COMMIT_FORMAT_INVALID: Message must match pattern: <type>(<scope>): <description>"
        audit_log "commit_format" "FAIL" "$msg" "Invalid format"
        return 1
    fi
    success "Commit format valid"
    return 0
}

# Rule 2: No Credential References in Commit
validate_no_credentials_in_commit() {
    local msg="$1"
    
    # Block patterns that look like credentials
    local patterns=(
        "password[=:]"
        "secret[=:]"
        "token[=:]"
        "api.?key[=:]"
        "\.env"
        "credentials"
        "private.?key"
        "BEGIN.*PRIVATE.*KEY"
    )
    
    for pattern in "${patterns[@]}"; do
        if echo "$msg" | grep -qi "$pattern"; then
            error "CREDENTIAL_DETECTED: Message contains credential reference: $pattern"
            audit_log "no_credentials" "FAIL" "$msg" "Credential reference found: $pattern"
            return 1
        fi
    done
    
    success "No credential references detected"
    return 0
}

# Rule 3: Has Required Metadata
validate_metadata() {
    local msg="$1"
    local commit_hash="$2"
    
    # If this is a significant commit (not just docs), require tracking info
    if [[ "$msg" =~ ^(feat|fix|refactor)': '* ]]; then
        # Should reference issue, epic, or ticket
        if ! echo "$msg" | grep -qiE '(#[0-9]+|epic|EPIC|ticket|issue)'; then
            warning "EPIC_REFERENCE_MISSING: Significant changes should reference issue #/epic"
            # Don't fail, but warn
        fi
    fi
    
    return 0
}

# Rule 4: Policy Scope Validation
validate_policy_scope() {
    local msg="$1"
    
    # If modifying .instructions.md or governance docs, must have approval indicator
    if echo "$msg" | grep -qiE '(governance|\.instructions|rbac|policy)'; then
        if ! echo "$msg" | grep -qE '\[APPROVED\]|\[POLICY\]'; then
            warning "POLICY_CHANGE_NOT_MARKED: Governance changes should be marked [POLICY] [APPROVED]"
            # Don't fail (pre-commit should have caught file changes)
        fi
    fi
    
    return 0
}

# Rule 5: No Forbidden Operations
validate_no_forbidden_ops() {
    local msg="$1"
    
    # These operations should NEVER be in a regular commit message
    local forbidden=(
        "disable.*audit"
        "bypass.*security"
        "skip.*validation"
        "disable.*governance"
        "remove.*enforcement"
    )
    
    for pattern in "${forbidden[@]}"; do
        if echo "$msg" | grep -qi "$pattern"; then
            error "FORBIDDEN_OPERATION: Message indicates forbidden operation: $pattern"
            audit_log "forbidden_op" "FAIL" "$msg" "Forbidden operation in message"
            return 1
        fi
    done
    
    return 0
}

# Rule 6: Author Validation (if signing enforced)
validate_author() {
    local author_name="$1"
    local author_email="$2"
    
    # Check: email should be corporate or service account
    if [[ ! "$author_email" =~ (@company\.com|@project\.iam\.gserviceaccount\.com|@.*\.iam\.gserviceaccount\.com) ]]; then
        warning "AUTHOR_UNVERIFIED: Author email not recognized corporate domain"
        # Don't strictly fail (could be external contributor)
    fi
    
    return 0
}

################################################################################
# MAIN VALIDATION
################################################################################

main() {
    local commit_msg="$1"
    local commit_hash="${2:-unknown}"
    
    if [ -z "$commit_msg" ]; then
        error "No commit message provided"
        exit 1
    fi
    
    log "Validating commit: $commit_hash"
    log "Message: $commit_msg"
    
    local failed=0
    
    # Run all validations (continue on failure to show all issues)
    validate_commit_format "$commit_msg" || failed=$((failed + 1))
    validate_no_credentials_in_commit "$commit_msg" || failed=$((failed + 1))
    validate_metadata "$commit_msg" "$commit_hash"
    validate_policy_scope "$commit_msg"
    validate_no_forbidden_ops "$commit_msg" || failed=$((failed + 1))
    
    # Optional: validate author
    if git config user.name >/dev/null 2>&1; then
        validate_author "$(git config user.name)" "$(git config user.email)"
    fi
    
    if [ $failed -gt 0 ]; then
        error "Commit validation failed with $failed error(s)"
        audit_log "commit_validation" "FAIL" "$commit_hash" "Multiple validation failures"
        exit 1
    fi
    
    success "Commit passed all validations"
    audit_log "commit_validation" "PASS" "$commit_hash" "All rules passed"
    exit 0
}

main "$@"
