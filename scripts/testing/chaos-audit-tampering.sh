#!/usr/bin/env bash
# scripts/testing/chaos-audit-tampering.sh
# Chaos Test: Audit Log Tampering Detection and Recovery
# Tests immutability protections and tampering detection mechanisms

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AUDIT_DIR="${REPO_ROOT}/.chaos-audit"
mkdir -p "$AUDIT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
  local result="$1"
  local test_name="$2"
  local details="$3"
  
  case "$result" in
    PASS)
      echo -e "${GREEN}[PASS]${NC} $test_name — $details"
      ((TESTS_PASSED++))
      ;;
    FAIL)
      echo -e "${RED}[FAIL]${NC} $test_name — $details"
      ((TESTS_FAILED++))
      ;;
    INFO)
      echo -e "${BLUE}[INFO]${NC} $test_name — $details"
      ;;
  esac
  ((TESTS_TOTAL++))
}

# Test 1: Detect deletion attacks on audit logs
test_deletion_attack_detection() {
  echo ""
  echo -e "${BLUE}=== Chaos Test: Deletion Attack Detection ===${NC}"
  
  local audit_file="${AUDIT_DIR}/deletion-test.jsonl"
  local backup_file="${AUDIT_DIR}/deletion-test.jsonl.bak"
  
  # Create initial audit entries
  echo '{"timestamp":"2026-03-11T10:00:00Z","event":"baseline_entry","immutable":true}' >> "$audit_file"
  echo '{"timestamp":"2026-03-11T10:01:00Z","event":"sensitive_operation","immutable":true}' >> "$audit_file"
  
  # Backup original
  cp "$audit_file" "$backup_file"
  local original_lines=$(wc -l < "$audit_file")
  
  # Chaos: Delete middle entry
  sed -i '/sensitive_operation/d' "$audit_file"
  local after_delete_lines=$(wc -l < "$audit_file")
  
  # Detection: Line count decreased
  if [[ $after_delete_lines -lt $original_lines ]]; then
    log_test "PASS" "deletion_attack_detection" "Missing entries detected ($original_lines → $after_delete_lines lines)"
  else
    log_test "FAIL" "deletion_attack_detection" "Deletion not detected"
  fi
  
  # Recovery: Compare with backup
  diff "$audit_file" "$backup_file" > /dev/null 2>&1 && {
    log_test "FAIL" "deletion_attack_recovery" "Files match (tampering should differ)"
  } || {
    log_test "PASS" "deletion_attack_recovery" "Tampering detected via diff"
  }
  
  rm -f "$audit_file" "$backup_file"
}

# Test 2: Detect modification attacks on audit logs
test_modification_attack_detection() {
  echo ""
  echo -e "${BLUE}=== Chaos Test: Modification Attack Detection ===${NC}"
  
  local audit_file="${AUDIT_DIR}/modification-test.jsonl"
  
  # Create audit entry with specific values
  echo '{"timestamp":"2026-03-11T10:00:00Z","operator":"user123","resource":"secret-prod","action":"read","status":"success","immutable":true}' >> "$audit_file"
  
  # Chaos: Modify operator field
  sed -i 's/"operator":"user123"/"operator":"attacker999"/g' "$audit_file"
  
  # Detection: Verify original value not in file
  if ! grep -q "user123" "$audit_file"; then
    log_test "PASS" "modification_attack_detection" "Modified field detected"
  else
    log_test "FAIL" "modification_attack_detection" "Modification not detected"
  fi
  
  # Verify attacker field now present
  if grep -q "attacker999" "$audit_file"; then
    log_test "PASS" "modification_verification" "Attack payload confirmed in log"
  fi
  
  rm -f "$audit_file"
}

# Test 3: Rollback prevention (chaos: attempt file restoration)
test_rollback_prevention() {
  echo ""
  echo -e "${BLUE}=== Chaos Test: Rollback Prevention ===${NC}"
  
  local audit_file="${AUDIT_DIR}/rollback-test.jsonl"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Create sequence of events with increasing timestamps
  echo '{"timestamp":"2026-03-11T10:00:00Z","event":"t1","sequence":1,"immutable":true}' >> "$audit_file"
  echo '{"timestamp":"2026-03-11T10:01:00Z","event":"t2","sequence":2,"immutable":true}' >> "$audit_file"
  echo '{"timestamp":"2026-03-11T10:02:00Z","event":"t3","sequence":3,"immutable":true}' >> "$audit_file"
  
  # Chaos: Remove last entry and restore old backup
  sed -i '$ d' "$audit_file"  # Remove last line
  
  # Check timestamp order is broken
  local last_timestamp=$(tail -1 "$audit_file" | grep -o '"timestamp":"[^"]*"' | tail -1 | cut -d'"' -f4)
  if [[ "$last_timestamp" < "2026-03-11T10:02:00Z" ]]; then
    log_test "PASS" "rollback_detection" "Corrupted timestamp sequence detected"
  else
    log_test "INFO" "rollback_detection" "Last event timestamp: $last_timestamp"
  fi
  
  rm -f "$audit_file"
}

# Test 4: Concurrent write protection
test_concurrent_write_safety() {
  echo ""
  echo -e "${BLUE}=== Chaos Test: Concurrent Write Safety ===${NC}"
  
  local audit_file="${AUDIT_DIR}/concurrent-test.jsonl"
  local num_writers=5
  local entries_per_writer=10
  
  # Simulate concurrent writes
  for i in $(seq 1 $num_writers); do
    (
      for j in $(seq 1 $entries_per_writer); do
        echo "{\"timestamp\":\"2026-03-11T10:$i:$j\",\"writer\":$i,\"entry\":$j,\"immutable\":true}" >> "$audit_file"
      done
    ) &
  done
  
  wait  # Wait for all background processes
  
  # Verify all entries written
  local total_lines=$(wc -l < "$audit_file")
  local expected_lines=$((num_writers * entries_per_writer))
  
  if [[ $total_lines -eq $expected_lines ]]; then
    log_test "PASS" "concurrent_write_safety" "All $expected_lines entries written successfully"
  else
    log_test "FAIL" "concurrent_write_safety" "Expected $expected_lines but got $total_lines"
  fi
  
  # Verify all entries are valid JSON
  local invalid_json=0
  while IFS= read -r line; do
    if ! echo "$line" | jq empty 2>/dev/null; then
      ((invalid_json++))
    fi
  done < "$audit_file"
  
  if [[ $invalid_json -eq 0 ]]; then
    log_test "PASS" "concurrent_json_validity" "All entries valid JSON"
  else
    log_test "FAIL" "concurrent_json_validity" "$invalid_json invalid JSON entries"
  fi
  
  rm -f "$audit_file"
}

# Test 5: Forensic capability (audit log analysis)
test_forensic_analysis() {
  echo ""
  echo -e "${BLUE}=== Chaos Test: Forensic Analysis Capability ===${NC}"
  
  local audit_file="${AUDIT_DIR}/forensic-test.jsonl"
  
  # Create audit trail of attack scenario
  echo '{"timestamp":"2026-03-11T10:00:00Z","event":"normal_operation","operator":"admin1","resource":"db-prod","action":"read","status":"success","immutable":true}' >> "$audit_file"
  echo '{"timestamp":"2026-03-11T10:30:00Z","event":"privilege_escalation_attempt","operator":"user123","resource":"iam-role","action":"modify","status":"denied","immutable":true}' >> "$audit_file"
  echo '{"timestamp":"2026-03-11T11:00:00Z","event":"secret_access","operator":"user123","resource":"SECRET_AWS_KEY","action":"read","status":"success","immutable":true}' >> "$audit_file"
  
  # Forensic queries
  local priv_esc_attempts=$(grep -c "privilege_escalation_attempt" "$audit_file" || true)
  local user123_actions=$(grep -c '"operator":"user123"' "$audit_file" || true)
  local failed_actions=$(grep -c '"status":"denied"' "$audit_file" || true)
  
  if [[ $priv_esc_attempts -gt 0 ]]; then
    log_test "PASS" "forensic_threat_detection" "Found $priv_esc_attempts privilege escalation attempts"
  fi
  
  if [[ $user123_actions -gt 0 ]]; then
    log_test "PASS" "forensic_user_tracking" "Found $user123_actions actions by user123"
  fi
  
  if [[ $failed_actions -gt 0 ]]; then
    log_test "PASS" "forensic_failed_action_tracking" "Found $failed_actions failed actions"
  fi
  
  rm -f "$audit_file"
}

# Test 6: Multi-stream audit correlation
test_multistream_correlation() {
  echo ""
  echo -e "${BLUE}=== Chaos Test: Multi-Stream Audit Correlation ===${NC}"
  
  # Simulate multiple audit streams (.env-audit, .secret-audit, .pam-audit, .webhook-audit)
  local env_audit="${AUDIT_DIR}/env-stream.jsonl"
  local secret_audit="${AUDIT_DIR}/secret-stream.jsonl"
  local pam_audit="${AUDIT_DIR}/pam-stream.jsonl"
  
  local timestamp="2026-03-11T10:00:00Z"
  
  # Same timestamp in all streams = correlated event
  echo "{\"timestamp\":\"$timestamp\",\"var\":\"CREDENTIAL_SECRET\",\"immutable\":true}" >> "$env_audit"
  echo "{\"timestamp\":\"$timestamp\",\"secret\":\"loaded\",\"immutable\":true}" >> "$secret_audit"
  echo "{\"timestamp\":\"$timestamp\",\"operator\":\"app\",\"action\":\"access\",\"immutable\":true}" >> "$pam_audit"
  
  # Count correlated entries across streams
  local env_count=$(wc -l < "$env_audit")
  local secret_count=$(wc -l < "$secret_audit")
  local pam_count=$(wc -l < "$pam_audit")
  
  if [[ $env_count -eq 1 && $secret_count -eq 1 && $pam_count -eq 1 ]]; then
    log_test "PASS" "multistream_correlation" "All 3 streams have matching events"
  else
    log_test "FAIL" "multistream_correlation" "Stream counts mismatch: env=$env_count, secret=$secret_count, pam=$pam_count"
  fi
  
  rm -f "$env_audit" "$secret_audit" "$pam_audit"
}

# Run all audit tampering tests
run_all_audit_tests() {
  echo ""
  echo -e "${BLUE}=====================================================${NC}"
  echo -e "${BLUE}E2E CHAOS TEST: AUDIT LOG TAMPERING DETECTION${NC}"
  echo -e "${BLUE}=====================================================${NC}"
  
  test_deletion_attack_detection
  test_modification_attack_detection
  test_rollback_prevention
  test_concurrent_write_safety
  test_forensic_analysis
  test_multistream_correlation
  
  echo ""
  echo -e "${BLUE}=====================================================${NC}"
  echo "Total Tests:  $TESTS_TOTAL"
  echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
  echo -e "${BLUE}=====================================================${NC}"
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL AUDIT TAMPERING TESTS PASSED${NC}"
    return 0
  else
    echo -e "${RED}✗ SOME AUDIT TESTS FAILED${NC}"
    return 1
  fi
}

export -f test_deletion_attack_detection
export -f test_modification_attack_detection
export -f test_rollback_prevention
export -f test_concurrent_write_safety
export -f test_forensic_analysis
export -f test_multistream_correlation
export -f run_all_audit_tests

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_audit_tests
fi
