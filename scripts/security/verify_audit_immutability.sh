#!/usr/bin/env bash
set -euo pipefail

# Audit Immutability Verification
# Validates JSONL audit logs with hash chain to ensure:
# 1. Append-only: no deletions or overwrites
# 2. Hash chain integrity: each entry references previous hash
# 3. Timestamps are monotonically increasing
# 4. KMS encryption metadata is present for all sensitive entries

AUDIT_LOG="${AUDIT_LOG:-.}"
VERIFICATION_LOG="${VERIFICATION_LOG:-/tmp/audit_verification_$(date +%s).jsonl}"

# Utility: log verification result as JSONL
log_verification() {
  local check="$1"
  local status="$2"  # PASS or FAIL
  local details="${3:-}"
  
  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg check "$check" \
    --arg status "$status" \
    --arg details "$details" \
    '{timestamp: $ts, check: $check, status: $status, details: $details}' \
    >> "$VERIFICATION_LOG"
}

# Check 1: JSONL format validity
check_jsonl_format() {
  echo "Verifying JSONL format..."
  
  local line_count=0
  local valid_lines=0
  
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    ((line_count++))
    
    if jq -e . >/dev/null 2>&1 <<<"$line"; then
      ((valid_lines++))
    fi
  done < "$AUDIT_LOG"
  
  if [ "$line_count" -eq "$valid_lines" ] && [ "$line_count" -gt 0 ]; then
    log_verification "jsonl_format_valid" "PASS" "All $line_count entries are valid JSON"
    return 0
  else
    log_verification "jsonl_format_valid" "FAIL" "Invalid JSON in audit log: $valid_lines of $line_count lines valid"
    return 1
  fi
}

# Check 2: Hash chain integrity (each entry has previous_hash reference)
check_hash_chain() {
  echo "Verifying hash chain integrity..."
  
  local prev_hash="0000000000000000000000000000000000000000"
  local line_num=0
  local valid_chain=0
  local broken=0
  
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    ((line_num++))
    
    local entry_hash=$(jq -r '.hash // empty' <<<"$line")
    local prev_ref=$(jq -r '.previous_hash // empty' <<<"$line")
    
    if [ -z "$entry_hash" ] || [ -z "$prev_ref" ]; then
      ((broken++))
      continue
    fi
    
    if [ "$prev_ref" == "$prev_hash" ]; then
      ((valid_chain++))
      prev_hash="$entry_hash"
    else
      ((broken++))
    fi
  done < "$AUDIT_LOG"
  
  if [ "$broken" -eq 0 ] && [ "$valid_chain" -gt 0 ]; then
    log_verification "hash_chain_integrity" "PASS" "Hash chain valid: $valid_chain entries linked correctly"
    return 0
  else
    log_verification "hash_chain_integrity" "FAIL" "Hash chain broken: $broken integrity violations found"
    return 1
  fi
}

# Check 3: Timestamps monotonically increasing
check_monotonic_timestamps() {
  echo "Verifying monotonic timestamps..."
  
  local prev_ts="1970-01-01T00:00:00Z"
  local violations=0
  
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    
    local ts=$(jq -r '.timestamp // empty' <<<"$line")
    
    if [ -z "$ts" ]; then
      ((violations++))
      continue
    fi
    
    if [[ "$ts" < "$prev_ts" ]]; then
      ((violations++))
      echo "  Timestamp violation: $ts after $prev_ts"
    fi
    
    prev_ts="$ts"
  done < "$AUDIT_LOG"
  
  if [ "$violations" -eq 0 ]; then
    log_verification "monotonic_timestamps" "PASS" "All timestamps are monotonically increasing"
    return 0
  else
    log_verification "monotonic_timestamps" "FAIL" "$violations timestamp violations found"
    return 1
  fi
}

# Check 4: KMS encryption metadata present for sensitive operations
check_kms_encryption_metadata() {
  echo "Verifying KMS encryption metadata..."
  
  local sensitive_ops=0
  local with_kms_metadata=0
  
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    
    local operation=$(jq -r '.operation // empty' <<<"$line")
    
    # Sensitive operations: credential_create, secret_rotate, secret_migrate
    if [[ "$operation" =~ ^(credential_create|secret_rotate|secret_migrate)$ ]]; then
      ((sensitive_ops++))
      
      local kms_key=$(jq -r '.kms_key_id // empty' <<<"$line")
      local encrypted=$(jq -r '.is_encrypted // empty' <<<"$line")
      
      if [ -n "$kms_key" ] && [ "$encrypted" == "true" ]; then
        ((with_kms_metadata++))
      fi
    fi
  done < "$AUDIT_LOG"
  
  if [ "$sensitive_ops" -eq "$with_kms_metadata" ]; then
    log_verification "kms_encryption_metadata" "PASS" "All $sensitive_ops sensitive operations have KMS metadata"
    return 0
  else
    log_verification "kms_encryption_metadata" "FAIL" "$with_kms_metadata of $sensitive_ops sensitive operations have KMS metadata"
    return 1
  fi
}

# Check 5: No deletions or overwrites (append-only)
check_append_only() {
  echo "Verifying append-only constraint..."
  
  local line_count=$(wc -l < "$AUDIT_LOG" | tr -d ' ')
  local unique_hashes=$(jq -r '.hash // empty' < "$AUDIT_LOG" | sort -u | wc -l)
  
  if [ "$line_count" -eq "$unique_hashes" ]; then
    log_verification "append_only" "PASS" "No duplicates or overwrites: $line_count unique entries"
    return 0
  else
    log_verification "append_only" "FAIL" "Duplicate hashes detected: $line_count lines vs $unique_hashes unique hashes"
    return 1
  fi
}

# Main: Run all checks
main() {
  echo "========================================"
  echo "Audit Immutability Verification"
  echo "========================================"
  echo "Audit log: $AUDIT_LOG"
  echo "Verification log: $VERIFICATION_LOG"
  echo ""
  
  if [ ! -f "$AUDIT_LOG" ]; then
    echo "❌ Audit log not found: $AUDIT_LOG"
    return 1
  fi
  
  local failed=0
  
  check_jsonl_format || ((failed++))
  check_hash_chain || ((failed++))
  check_monotonic_timestamps || ((failed++))
  check_kms_encryption_metadata || ((failed++))
  check_append_only || ((failed++))
  
  echo ""
  echo "========================================"
  echo "Verification Summary"
  echo "========================================"
  cat "$VERIFICATION_LOG" | jq -s '{total: length, passed: map(select(.status == "PASS")) | length, failed: map(select(.status == "FAIL")) | length, checks: .}'
  echo ""
  
  if [ "$failed" -gt 0 ]; then
    echo "❌ $failed verification(s) failed."
    return 1
  else
    echo "✅ All audit immutability checks passed!"
    return 0
  fi
}

main "$@"
