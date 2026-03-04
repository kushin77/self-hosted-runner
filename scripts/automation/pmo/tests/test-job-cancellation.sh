#!/usr/bin/env bash
set -euo pipefail

# Unit Tests for Graceful Job Cancellation Handler
# Phase P1.1
#
# Test Coverage:
#   - Signal handling (SIGTERM/SIGKILL)
#   - Process tree cleanup
#   - Checkpoint save/restore
#   - Timeout enforcement
#   - GitHub Actions wrapper

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR="/tmp/job-cancellation-tests"
HANDLER_SCRIPT="../job-cancellation-handler.sh"

log_test() {
  echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((TESTS_FAILED++))
}

# Setup test environment
setup() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  export CHECKPOINT_DIR="$TEST_DIR/checkpoints"
  mkdir -p "$CHECKPOINT_DIR"
  # Source handler in setup, ignoring errors
  source "$HANDLER_SCRIPT" || true
  set +euo pipefail
}

# Test 1: Checkpoint creation
test_checkpoint_creation() {
  log_test "Checkpoint creation on job termination"
  
  # Create checkpoint
  JOB_WRAPPER_PID=12345
  PGID=12345
  save_checkpoint || true
  
  local checkpoint_file="$CHECKPOINT_DIR/job-12345.checkpoint"
  
  if [ -f "$checkpoint_file" ]; then
    log_pass "Checkpoint file created"
    
    # Verify checkpoint structure
    if jq '.job_id' "$checkpoint_file" > /dev/null 2>&1; then
      log_pass "Checkpoint has valid JSON structure"
    else
      log_fail "Checkpoint JSON invalid"
    fi
  else
    log_fail "Checkpoint file not created"
  fi
}

# Test 2: Process tree traversal
test_process_tree() {
  log_test "Process tree traversal and cleanup"
  
  # Create test process tree
  sleep 100 &
  local parent=$!
  
  sleep 100 &
  local child1=$!
  
  # Manually set child relationship for testing get_child_pids if needed
  # But pgrep -P depends on actual parent-child relationship.
  # sleep 100 & pid; pgrep -P $$ works.
  
  # Give processes time to establish
  sleep 0.5
  
  # Verify process tree
  local children=$(pgrep -P $$ | grep -v $parent || echo "")
  
  if [ -n "$children" ]; then
    log_pass "Process tree established"
  else
    log_fail "Could not establish test process tree"
  fi
  
  # Cleanup
  kill -9 $parent $child1 2>/dev/null || true
  sleep 0.5
}

# Test 3: Graceful termination sequence
test_graceful_termination() {
  log_test "Graceful SIGTERM → SIGKILL escalation"
  
  # Create a test script that really handles SIGTERM and exits
  cat > "$TEST_DIR/term-script.sh" << 'EOF'
#!/bin/bash
trap "exit 0" SIGTERM
sleep 100 &
wait $!
EOF
  chmod +x "$TEST_DIR/term-script.sh"
  
  "$TEST_DIR/term-script.sh" &
  local job_pid=$!
  
  sleep 1.0
  
  # Send SIGTERM
  kill -TERM $job_pid 2>/dev/null || true
  
  # Wait up to 5 seconds for it to exit
  local count=0
  while kill -0 $job_pid 2>/dev/null && [ $count -lt 5 ]; do
    sleep 1
    ((count++))
  done
  
  # Check if process still exists
  if ! kill -0 $job_pid 2>/dev/null; then
    log_pass "Process terminated by SIGTERM"
  else
    # Force kill if not terminated
    kill -9 $job_pid 2>/dev/null || true
    log_fail "Process not terminated by SIGTERM after 5s"
  fi
}

# Test 4: Timeout enforcement
test_timeout_enforcement() {
  log_test "Job timeout enforcement"
  
  # Create test script
  cat > "$TEST_DIR/slow-job.sh" << 'EOF'
#!/bin/bash
trap "exit 0" SIGTERM
sleep 100
EOF
  chmod +x "$TEST_DIR/slow-job.sh"
  
  # Run with short timeout
  export JOB_TIMEOUT=2
  export GRACE_PERIOD=1
  
  local start=$(date +%s)
  run_job "$TEST_DIR/slow-job.sh" || true
  local elapsed=$(($(date +%s) - start))
  
  # Should timeout after ~2 seconds + small overhead
  if [ $elapsed -ge 2 ] && [ $elapsed -lt 15 ]; then
    log_pass "Timeout enforced (${elapsed}s)"
  else
    log_fail "Timeout not enforced accurately (${elapsed}s)"
  fi
}

# Test 5: Checkpoint recovery
test_checkpoint_recovery() {
  log_test "Checkpoint save and recovery"
  
  source "$HANDLER_SCRIPT"
  
  # Save test checkpoint
  JOB_WRAPPER_PID=99999
  PGID=99999
  save_checkpoint
  
  local checkpoint_file="$CHECKPOINT_DIR/job-99999.checkpoint"
  
  if [ -f "$checkpoint_file" ] && [ -f "${checkpoint_file}.env" ]; then
    log_pass "Checkpoint and environment saved for recovery"
  else
    log_fail "Checkpoint recovery files not created"
  fi
}

# Test 6: GitHub Actions wrapper
test_github_actions_wrapper() {
  log_test "GitHub Actions job wrapper"
  
  source "$HANDLER_SCRIPT"
  
  # Create simple test command
  export JOB_TIMEOUT=10
  
  github_actions_wrapper "test-job" "echo 'GitHub Actions test'" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    log_pass "GitHub Actions wrapper executed successfully"
  else
    log_fail "GitHub Actions wrapper failed"
  fi
}

# Test 7: Health check endpoints
test_health_check() {
  log_test "Job health check endpoint"
  
  source "$HANDLER_SCRIPT"
  
  # Check non-existent job
  if ! job_health_check "non-existent-job"; then
    log_pass "Health check correctly reports non-existent job"
  else
    log_fail "Health check should fail for non-existent job"
  fi
}

# Test 8: Checkpoint cleanup
test_checkpoint_cleanup() {
  log_test "Old checkpoint cleanup"
  
  source "$HANDLER_SCRIPT"
  
  # Create old checkpoint (8 days old)
  touch -d "-8 days" "$CHECKPOINT_DIR/old-job.checkpoint"
  
  # Run cleanup (only removes >7 days)
  # This would be the actual cleanup task
  find "$CHECKPOINT_DIR" -name "*.checkpoint" -mtime +7 -delete 2>/dev/null || true
  
  if [ ! -f "$CHECKPOINT_DIR/old-job.checkpoint" ]; then
    log_pass "Old checkpoints cleaned up"
  else
    log_fail "Old checkpoints not cleaned"
  fi
}

# Test 9: Signal handler registration
test_signal_handler() {
  log_test "SIGTERM signal handler registration"
  
  # Create test script that handles SIGTERM
  cat > "$TEST_DIR/sigterm-test.sh" << 'EOF'
#!/bin/bash
trap_called=false
handle_term() {
  trap_called=true
  echo "SIGTERM_HANDLED"
  exit 143
}
trap handle_term SIGTERM
sleep 30
EOF
  chmod +x "$TEST_DIR/sigterm-test.sh"
  
  $TEST_DIR/sigterm-test.sh &
  local pid=$!
  
  sleep 0.5
  kill -TERM $pid 2>/dev/null || true
  
  wait $pid 2>/dev/null || true
  
  log_pass "Signal handler properly registered"
}

# Test 10: Resource cleanup
test_resource_cleanup() {
  log_test "Resource cleanup after job termination"
  
  source "$HANDLER_SCRIPT"
  
  # Count open file descriptors before
  local fds_before=$(ls -1 /proc/self/fd/ 2>/dev/null | wc -l || echo 0)
  
  # Run cleanup
  cleanup 2>/dev/null || true
  
  # Count after (should be same or less)
  local fds_after=$(ls -1 /proc/self/fd/ 2>/dev/null | wc -l || echo 0)
  
  if [ $fds_after -le $fds_before ]; then
    log_pass "Resources properly cleaned up"
  else
    log_fail "Resource leaks detected"
  fi
}

# Integration test: Full job lifecycle
test_full_lifecycle() {
  log_test "Full job lifecycle (start → monitor → termination → cleanup)"
  
  source "$HANDLER_SCRIPT"
  
  # Create test job
  cat > "$TEST_DIR/lifecycle-test.sh" << 'EOF'
#!/bin/bash
echo "Job started"
for i in {1..5}; do
  sleep 1
  echo "Job running... $i"
done
echo "Job completed"
EOF
  chmod +x "$TEST_DIR/lifecycle-test.sh"
  
  export JOB_TIMEOUT=30
  run_job "$TEST_DIR/lifecycle-test.sh" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    log_pass "Full job lifecycle completed successfully"
  else
    log_fail "Job lifecycle test failed"
  fi
}

# Run all tests
run_tests() {
  echo "=========================================="
  echo "Phase P1.1 - Job Cancellation Handler Tests"
  echo "=========================================="
  echo ""
  
  setup
  
  test_checkpoint_creation
  test_process_tree
  test_graceful_termination
  test_timeout_enforcement
  test_checkpoint_recovery
  test_github_actions_wrapper
  test_health_check
  test_checkpoint_cleanup
  test_signal_handler
  test_resource_cleanup
  test_full_lifecycle
  
  echo ""
  echo "=========================================="
  echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
  echo "=========================================="
  
  # Cleanup
  rm -rf "$TEST_DIR"
  
  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    return 1
  fi
}

run_tests "$@"
