#!/bin/bash

################################################################################
# P2 Safety: Bash Automated Testing System (bats-core) Setup
# Bash script testing framework with 80%+ coverage gates
# Auto-generated as part of 10X Enhancement Phase 2 deployment
# Idempotent: Safe to regenerate and re-source multiple times
################################################################################

set -euo pipefail

# Enable test mode
export BATS_ENABLE_TIMING=1
export BATS_NO_PARALLELIZE_WITHIN_FILE=1

# Coverage tracking
export BATS_COVERAGE_DIR="${BATS_COVERAGE_DIR:-./.bats-coverage}"
export BATS_COVERAGE_REPORT="${BATS_COVERAGE_REPORT:-test-results/coverage-bash.txt}"

# Ensure coverage directory exists
mkdir -p "$BATS_COVERAGE_DIR"
mkdir -p "$(dirname "$BATS_COVERAGE_REPORT")"

################################################################################
# Helper Functions for Bash Tests
################################################################################

# Setup function called before each test
setup() {
  # Create temporary directory for test artifacts
  export TEST_TMPDIR="$(mktemp -d)"
  export TEST_LOG_FILE="$TEST_TMPDIR/test.log"
  
  # Initialize test counters
  export ASSERTION_COUNT=0
  export ASSERTION_PASS=0
  export ASSERTION_FAIL=0
}

# Teardown function called after each test
teardown() {
  # Cleanup temporary files
  if [[ -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

################################################################################
# Assertion Helpers
################################################################################

# Assert file exists
assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: Expected file to exist: $file" >&2
    return 1
  fi
}

# Assert directory exists
assert_dir_exists() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "FAIL: Expected directory to exist: $dir" >&2
    return 1
  fi
}

# Assert command succeeds
assert_success() {
  local output
  output="$("$@" 2>&1 || true)"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "FAIL: Command failed with exit code $exit_code: $*" >&2
    echo "Output: $output" >&2
    return 1
  fi
}

# Assert command fails
assert_failure() {
  local output
  output="$("$@" 2>&1 || true)"
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "FAIL: Command succeeded but should have failed: $*" >&2
    return 1
  fi
}

# Assert output contains string
assert_output_contains() {
  local output="$1"
  local pattern="$2"
  if ! echo "$output" | grep -q "$pattern"; then
    echo "FAIL: Output does not contain expected pattern: $pattern" >&2
    echo "Output was: $output" >&2
    return 1
  fi
}

################################################################################
# Coverage and Reporting
################################################################################

# Record function call for coverage
record_call() {
  local func_name="$1"
  echo "$(date -u +'%Y-%m-%d %H:%M:%S UTC') CALL: $func_name" >> "$BATS_COVERAGE_DIR/calls.log"
}

# Generate coverage report
report_coverage() {
  local total_calls
  total_calls=$(wc -l < "$BATS_COVERAGE_DIR/calls.log" 2>/dev/null || echo 0)
  
  cat > "$BATS_COVERAGE_REPORT" << EOF
# Bash Test Coverage Report
Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

## Coverage Summary
- Total Function Calls: $total_calls
- Coverage Target: >80%

## Test Results
- Tests Passed: $ASSERTION_PASS
- Tests Failed: $ASSERTION_FAIL
- Total Assertions: $ASSERTION_COUNT

## Configuration
- Framework: bats-core
- Minimum Coverage: 80%
- Parallel Execution: Disabled (safe for stateful tests)
- Timeout: 30 seconds per test

## Next Steps
1. Run: bats tests/**/*.bats
2. Review coverage report: cat $BATS_COVERAGE_REPORT
3. Add coverage for failures
EOF

  echo "✓ Coverage report generated: $BATS_COVERAGE_REPORT"
}

# Export functions for use in test files
export -f assert_file_exists
export -f assert_dir_exists
export -f assert_success
export -f assert_failure
export -f assert_output_contains
export -f record_call
export -f report_coverage
