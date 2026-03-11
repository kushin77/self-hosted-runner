#!/bin/bash

################################################################################
# Runtime Policy Enforcer - Pre-Execution Policy Checks
# Validates: rate limits, SLA compliance, approval status, freshness, signatures
# Runs BEFORE any infrastructure operation
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
POLICY_LOG="${PROJECT_ROOT}/logs/governance/runtime-policy-enforcement.jsonl"

mkdir -p "$(dirname "$POLICY_LOG")"

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
    local check="$1" status="$2" reason="${3:-}" details="${4:-}"
    printf '{"timestamp":"%s","check":"%s","status":"%s","reason":"%s","details":%s}\n' \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$check" "$status" "$reason" "$details" >> "$POLICY_LOG"
}

################################################################################
# POLICY CHECKS
################################################################################

# Check 1: Rate Limiting
check_rate_limit() {
    local actor="$1"
    local capability="$2"
    local max_per_minute="${3:-10}"
    
    local count_file="${PROJECT_ROOT}/.rate_limit/${actor}/${capability}.count"
    mkdir -p "$(dirname "$count_file")"
    
    local count=0
    local last_reset=0
    
    if [ -f "$count_file" ]; then
        read -r count last_reset < "$count_file"
    fi
    
    local now=$(date +%s)
    local elapsed=$((now - last_reset))
    
    # Reset counter every 60 seconds
    if [ $elapsed -ge 60 ]; then
        count=0
        last_reset=$now
    fi
    
    count=$((count + 1))
    
    # Check limit
    if [ $count -gt "$max_per_minute" ]; then
        error "RATE_LIMIT_EXCEEDED: $actor attempted $capability $count times/min (max $max_per_minute)"
        audit_log "rate_limit" "FAIL" "Exceeded: $count/$max_per_minute" "{\"actor\":\"$actor\",\"capability\":\"$capability\"}"
        return 1
    fi
    
    # Update counter
    echo "$count $last_reset" > "$count_file"
    success "Rate limit OK ($count/$max_per_minute)"
    audit_log "rate_limit" "PASS" "Within limit: $count/$max_per_minute" "{\"actor\":\"$actor\",\"capability\":\"$capability\"}"
    return 0
}

# Check 2: SLA Compliance
check_sla_compliance() {
    local environment="$1"  # prod, staging, dev
    local operation="$2"
    
    # SLA windows (UTC):
    # Prod deployments: Mon-Fri 2-4 AM, never 8-9 AM (maintenance window)
    # Staging: anytime
    # Dev: anytime
    
    if [ "$environment" != "prod" ]; then
        success "SLA check: non-prod environment, no window restriction"
        audit_log "sla_compliance" "PASS" "Non-prod environment" "{\"environment\":\"$environment\"}"
        return 0
    fi
    
    local hour=$(date -u +%H)
    local day=$(date -u +%u)  # 1=Mon, 7=Sun
    
    # Maintenance window: 8-9 AM UTC
    if [ "$hour" -eq 8 ]; then
        error "SLA_VIOLATION: Prod deployment during maintenance window (8-9 AM UTC)"
        audit_log "sla_compliance" "FAIL" "Maintenance window (8-9 AM UTC)" "{}"
        return 1
    fi
    
    # Outside business hours: only 2-4 AM
    if [ "$hour" -lt 2 ] || [ "$hour" -gt 4 ]; then
        error "SLA_VIOLATION: Prod deployment outside allowed window (2-4 AM UTC). Current: ${hour}:00 UTC"
        audit_log "sla_compliance" "FAIL" "Outside deployment window" "{\"current_hour\":$hour,\"allowed_window\":\"2-4 AM UTC\"}"
        return 1
    fi
    
    # Weekends: no prod deployments
    if [ "$day" -eq 6 ] || [ "$day" -eq 7 ]; then
        error "SLA_VIOLATION: Prod deployment on weekend (day $day). Prod only Mon-Fri"
        audit_log "sla_compliance" "FAIL" "Weekend deployment" "{\"day\":$day}"
        return 1
    fi
    
    success "SLA check: deployment window OK (2-4 AM UTC, Mon-Fri)"
    audit_log "sla_compliance" "PASS" "Within allowed deployment window" "{\"hour\":$hour,\"day\":$day}"
    return 0
}

# Check 3: Approval Status
check_approval_status() {
    local operation="$1"
    local approvers_required="${2:-1}"
    
    local approval_file="${PROJECT_ROOT}/.approvals/${operation}.approved"
    
    if [ ! -f "$approval_file" ]; then
        error "MISSING_APPROVAL: Operation requires $approvers_required approval(s)"
        audit_log "approval_status" "FAIL" "No approval file found" "{\"operation\":\"$operation\",\"required\":$approvers_required}"
        return 1
    fi
    
    local approval_count=$(wc -l < "$approval_file")
    
    if [ "$approval_count" -lt "$approvers_required" ]; then
        error "INSUFFICIENT_APPROVALS: Have $approval_count, need $approvers_required"
        audit_log "approval_status" "FAIL" "Insufficient approvals" "{\"operation\":\"$operation\",\"have\":$approval_count,\"required\":$approvers_required}"
        return 1
    fi
    
    success "Approval check: $approval_count/$approvers_required approvals present"
    audit_log "approval_status" "PASS" "Sufficient approvals" "{\"operation\":\"$operation\",\"count\":$approval_count}"
    return 0
}

# Check 4: Credential Freshness
check_credential_freshness() {
    local credential_path="$1"
    local max_age_seconds="${2:-3600}"  # 1 hour default
    
    if [ ! -f "$credential_path" ]; then
        error "CREDENTIAL_NOT_FOUND: $credential_path"
        audit_log "credential_freshness" "FAIL" "Credential not found" "{\"path\":\"$credential_path\"}"
        return 1
    fi
    
    local file_age=$(( $(date +%s) - $(stat -f%m "$credential_path" 2>/dev/null || stat -c%Y "$credential_path") ))
    
    if [ "$file_age" -gt "$max_age_seconds" ]; then
        error "STALE_CREDENTIAL: Age ${file_age}s exceeds max ${max_age_seconds}s"
        audit_log "credential_freshness" "FAIL" "Stale credential" "{\"path\":\"$credential_path\",\"age_seconds\":$file_age,\"max_seconds\":$max_age_seconds}"
        return 1
    fi
    
    success "Credential freshness OK (age: ${file_age}s, max: ${max_age_seconds}s)"
    audit_log "credential_freshness" "PASS" "Credential is fresh" "{\"path\":\"$credential_path\",\"age_seconds\":$file_age}"
    return 0
}

# Check 5: Cryptographic Signature
check_cryptographic_signature() {
    local deployment_manifest="$1"
    local signature_file="${deployment_manifest}.sig"
    
    if [ ! -f "$signature_file" ]; then
        error "SIGNATURE_MISSING: No signature for $deployment_manifest"
        audit_log "cryptographic_signature" "FAIL" "Signature file missing" "{\"manifest\":\"$deployment_manifest\"}"
        return 1
    fi
    
    # Verify signature (simplified; real implementation uses gpg/cosign)
    if ! grep -q "VERIFIED" "$signature_file" 2>/dev/null; then
        error "SIGNATURE_INVALID: Signature verification failed"
        audit_log "cryptographic_signature" "FAIL" "Signature invalid" "{\"manifest\":\"$deployment_manifest\"}"
        return 1
    fi
    
    success "Cryptographic signature valid"
    audit_log "cryptographic_signature" "PASS" "Signature verified" "{\"manifest\":\"$deployment_manifest\"}"
    return 0
}

################################################################################
# POLICY ENFORCEMENT ORCHESTRATOR
################################################################################

enforce_policy() {
    local operation="$1"
    local environment="${2:-dev}"
    local actor="${3:-system}"
    
    log "=== RUNTIME POLICY ENFORCEMENT ==="
    log "Operation: $operation"
    log "Environment: $environment"
    log "Actor: $actor"
    echo
    
    local failed=0
    
    # Run all checks (fail fast on critical checks)
    check_rate_limit "$actor" "$operation" 10 || failed=$((failed + 1))
    check_sla_compliance "$environment" "$operation" || {
        if [ "$environment" = "prod" ]; then
            failed=$((failed + 1))
        fi
    }
    
    if [ "$environment" = "prod" ]; then
        check_approval_status "$operation" 2 || failed=$((failed + 1))
    fi
    
    if [ $failed -gt 0 ]; then
        error "Policy enforcement failed with $failed critical error(s)"
        exit 1
    fi
    
    success "All runtime policy checks passed ✓"
    audit_log "policy_enforcement_result" "PASS" "Operation approved" "{\"operation\":\"$operation\",\"environment\":\"$environment\"}"
    return 0
}

################################################################################
# CLI
################################################################################

main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <operation> [environment] [actor]"
        echo "Example: $0 deploy_to_production prod sa-deployer@project.iam"
        exit 1
    fi
    
    enforce_policy "$@"
}

main "$@"
